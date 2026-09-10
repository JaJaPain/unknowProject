import sys
import os
import re
import ast
import json

# Ensure stdout and stderr use UTF-8 on Windows console
if sys.platform.startswith("win"):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='backslashreplace')
        sys.stderr.reconfigure(encoding='utf-8', errors='backslashreplace')
    except AttributeError:
        # Older python versions might not have reconfigure
        pass

# Configuration
IGNORED_DIRS = {
    ".git", "__pycache__", "node_modules", ".godot", "venv", 
    ".gemini", ".claude", ".tmp_godot_perf", ".tmp_godot_perf_monitor",
    ".tmp_godot_test", ".tmp_godot_user"
}

IGNORED_FILE_EXTENSIONS = {
    ".pyc", ".png", ".jpg", ".jpeg", ".tscn", ".import", ".svg", 
    ".wav", ".ogg", ".mp3", ".pck", ".cfg", ".zip", ".tar.gz", ".gitattributes"
}

def join_multiline_signatures(content):
    """
    Joins lines where there are open parentheses, brackets, or braces,
    while preserving the indentation of the starting line.
    """
    lines = content.splitlines()
    joined_lines = []
    current_line = ""
    current_indent = ""
    paren_count = 0
    bracket_count = 0
    brace_count = 0
    
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
            
        if paren_count == 0 and bracket_count == 0 and brace_count == 0:
            # Start of a new logical line, preserve its indentation
            indent_match = re.match(r"^([ \t]*)", line)
            current_indent = indent_match.group(1) if indent_match else ""
            current_line = stripped
        else:
            current_line += " " + stripped
            
        paren_count += stripped.count("(") - stripped.count(")")
        bracket_count += stripped.count("[") - stripped.count("]")
        brace_count += stripped.count("{") - stripped.count("}")
        
        if paren_count <= 0 and bracket_count <= 0 and brace_count <= 0:
            joined_lines.append(current_indent + current_line)
            current_line = ""
            current_indent = ""
            paren_count = 0
            bracket_count = 0
            brace_count = 0
            
    if current_line:
        joined_lines.append(current_indent + current_line)
        
    return "\n".join(joined_lines)


def get_python_function_signature(node):
    """Generates a clean string signature for a Python AST function node."""
    args = []
    
    # Positional-only args (Python 3.8+)
    posonlyargs = getattr(node.args, 'posonlyargs', [])
    for a in posonlyargs:
        args.append(a.arg)
    if posonlyargs:
        args.append('/')
    
    # Standard positional/keyword args
    for a in node.args.args:
        args.append(a.arg)
        
    # Varargs (*args)
    if node.args.vararg:
        args.append(f"*{node.args.vararg.arg}")
        
    # Keyword-only args
    kwonlyargs = getattr(node.args, 'kwonlyargs', [])
    if kwonlyargs and not node.args.vararg:
        args.append('*')
    for a in kwonlyargs:
        args.append(a.arg)
        
    # Kwargs (**kwargs)
    if node.args.kwarg:
        args.append(f"**{node.args.kwarg.arg}")
        
    args_str = ", ".join(args)
    prefix = "async def" if isinstance(node, ast.AsyncFunctionDef) else "def"
    return f"{prefix} {node.name}({args_str})"


def parse_python(file_content):
    """Parses a Python file using the ast module to extract classes and functions."""
    classes = []
    functions = []
    try:
        tree = ast.parse(file_content)
        for node in ast.iter_child_nodes(tree):
            if isinstance(node, ast.ClassDef):
                methods = []
                for subnode in ast.iter_child_nodes(node):
                    if isinstance(subnode, (ast.FunctionDef, ast.AsyncFunctionDef)):
                        sig = get_python_function_signature(subnode)
                        methods.append(sig)
                classes.append({"name": node.name, "methods": methods})
            elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                sig = get_python_function_signature(node)
                functions.append(sig)
    except Exception:
        pass
    return classes, functions


def parse_gdscript(file_content):
    """Parses GDScript files for class names, inner classes, and functions."""
    classes = []
    functions = []
    file_class_name = None
    
    lines = file_content.splitlines()
    
    # Find global class_name first
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        m = re.match(r"^class_name\s+(\w+)", stripped)
        if m:
            file_class_name = m.group(1)
            break
            
    class_stack = []
    
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
            
        # Determine indentation level
        indent_match = re.match(r"^([ \t]*)", line)
        indent_str = indent_match.group(1) if indent_match else ""
        indent_level = len(indent_str.replace("\t", "    "))
        
        while class_stack and indent_level <= class_stack[-1][1]:
            class_stack.pop()
            
        # Match inner classes
        class_match = re.match(r"^class\s+(\w+)", stripped)
        if class_match:
            c_name = class_match.group(1)
            class_stack.append((c_name, indent_level))
            classes.append({"name": c_name, "methods": []})
            continue
            
        # Match functions
        func_match = re.match(r"^(static\s+)?func\s+(\w+)\s*\((.*)\)(?:\s*->\s*([\w.]+))?:", stripped)
        if func_match:
            is_static = func_match.group(1) is not None
            func_name = func_match.group(2)
            func_args = func_match.group(3).strip()
            ret_type = func_match.group(4)
            
            sig = f"{func_name}({func_args})"
            if ret_type:
                sig += f" -> {ret_type}"
            full_sig = f"static func {sig}" if is_static else f"func {sig}"
            
            if class_stack:
                current_inner_class_name = class_stack[-1][0]
                for c in classes:
                    if c["name"] == current_inner_class_name:
                        c["methods"].append(full_sig)
                        break
            else:
                functions.append(full_sig)
                
    if file_class_name:
        classes.insert(0, {
            "name": f"global class {file_class_name}",
            "methods": functions
        })
        functions = []
        
    return classes, functions


def parse_javascript(file_content):
    """Parses JavaScript/TypeScript files for classes and functions/methods."""
    classes = []
    functions = []
    
    lines = file_content.splitlines()
    brace_depth = 0
    class_stack = []
    
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
            continue
            
        open_braces = stripped.count("{")
        close_braces = stripped.count("}")
        
        # Check for class declaration
        class_match = re.search(r"\bclass\s+(\w+)", stripped)
        if class_match:
            class_name = class_match.group(1)
            class_stack.append({
                "name": class_name,
                "brace_depth": brace_depth,
                "methods": []
            })
            
        # Match function declarations
        func_match = re.search(r"\b(async\s+)?function\s+(\w+)\s*\(", stripped)
        arrow_match = re.search(r"\b(const|let|var)\s+(\w+)\s*=\s*(async\s*)?\(.*?\)\s*=>", stripped)
        
        if func_match:
            is_async = func_match.group(1) is not None
            func_name = func_match.group(2)
            param_match = re.search(r"function\s+\w+\s*(\(.*?\))", stripped)
            params = param_match.group(1) if param_match else "()"
            prefix = "async function" if is_async else "function"
            sig = f"{prefix} {func_name}{params}"
            if class_stack:
                class_stack[-1]["methods"].append(sig)
            else:
                functions.append(sig)
        elif arrow_match:
            func_name = arrow_match.group(2)
            is_async = arrow_match.group(3) is not None
            param_match = re.search(r"=\s*(async\s*)?(\(.*?\))\s*=>", stripped)
            params = param_match.group(2) if param_match else "()"
            prefix = "async const" if is_async else "const"
            sig = f"{prefix} {func_name} = {params} => ..."
            if class_stack:
                class_stack[-1]["methods"].append(sig)
            else:
                functions.append(sig)
        elif class_stack:
            # Match methods inside a class
            method_match = re.match(r"^(async\s+)?(static\s+)?(\w+)\s*(\(.*?\))\s*\{?", stripped)
            if method_match:
                prefix_async = method_match.group(1) or ""
                prefix_static = method_match.group(2) or ""
                method_name = method_match.group(3)
                params = method_match.group(4)
                
                if method_name not in ("if", "for", "while", "switch", "catch", "function"):
                    prefixes = f"{prefix_async}{prefix_static}".strip()
                    prefix_str = f"{prefixes} " if prefixes else ""
                    sig = f"{prefix_str}{method_name}{params}"
                    class_stack[-1]["methods"].append(sig)
                    
        brace_depth += open_braces - close_braces
        
        while class_stack and brace_depth <= class_stack[-1]["brace_depth"]:
            finished_class = class_stack.pop()
            classes.append({
                "name": finished_class["name"],
                "methods": finished_class["methods"]
            })
            
    while class_stack:
        finished_class = class_stack.pop()
        classes.append({
            "name": finished_class["name"],
            "methods": finished_class["methods"]
        })
        
    return classes, functions


def parse_csharp(file_content):
    """Parses C# files for classes and method signatures."""
    classes = []
    functions = []
    
    lines = file_content.splitlines()
    brace_depth = 0
    class_stack = []
    
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
            continue
            
        open_braces = stripped.count("{")
        close_braces = stripped.count("}")
        
        class_match = re.search(r"\b(class|struct|interface)\s+(\w+)", stripped)
        if class_match:
            c_name = class_match.group(2)
            c_type = class_match.group(1)
            class_stack.append({
                "name": f"{c_type} {c_name}",
                "brace_depth": brace_depth,
                "methods": []
            })
        elif class_stack:
            method_match = re.match(r"^((?:public|private|protected|internal|static|override|virtual|async|unsafe)\s+)*([\w<>\s\[\]]+)\s+(\w+)\s*(\(.*?\))\s*\{?", stripped)
            if method_match:
                modifiers = method_match.group(1) or ""
                ret_type = method_match.group(2).strip()
                method_name = method_match.group(3)
                params = method_match.group(4)
                
                if method_name not in ("if", "for", "foreach", "while", "switch", "catch", "using", "lock") and ret_type not in ("new", "return", "class"):
                    prefix = modifiers.strip()
                    prefix_str = f"{prefix} " if prefix else ""
                    sig = f"{prefix_str}{ret_type} {method_name}{params}"
                    class_stack[-1]["methods"].append(sig)
                    
        brace_depth += open_braces - close_braces
        
        while class_stack and brace_depth <= class_stack[-1]["brace_depth"]:
            finished_class = class_stack.pop()
            classes.append({
                "name": finished_class["name"],
                "methods": finished_class["methods"]
            })
            
    while class_stack:
        finished_class = class_stack.pop()
        classes.append({
            "name": finished_class["name"],
            "methods": finished_class["methods"]
        })
        
    return classes, functions


def parse_file(file_path):
    """Determines parser based on file extension and returns symbols."""
    ext = os.path.splitext(file_path)[1].lower()
    try:
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
    except Exception:
        return None
        
    if not content.strip():
        return {"classes": [], "functions": []}
        
    if ext == ".py":
        classes, functions = parse_python(content)
    elif ext == ".gd":
        classes, functions = parse_gdscript(content)
    elif ext in (".js", ".ts", ".jsx", ".tsx"):
        classes, functions = parse_javascript(content)
    elif ext == ".cs":
        classes, functions = parse_csharp(content)
    else:
        return None
        
    return {"classes": classes, "functions": functions}


def build_tree(dir_path, base_path, visited_paths=None):
    """Recursively builds the codebase hierarchy tree, skipping ignored items."""
    if visited_paths is None:
        visited_paths = set()
        
    canonical_path = os.path.realpath(dir_path)
    if canonical_path in visited_paths:
        return None
    visited_paths.add(canonical_path)
    
    # Print progress
    rel_dir = os.path.relpath(dir_path, base_path)
    if rel_dir != ".":
        print(f"Scanning directory: {rel_dir}")
        
    node = {
        "type": "directory",
        "name": os.path.basename(dir_path) or dir_path,
        "children": []
    }
    
    try:
        entries = sorted(os.listdir(dir_path))
    except Exception:
        return None
        
    for entry in entries:
        full_path = os.path.join(dir_path, entry)
        rel_path = os.path.relpath(full_path, base_path)
        
        # Skip symlinks to avoid directory loops
        if os.path.islink(full_path):
            continue
            
        if os.path.isdir(full_path):
            if entry in IGNORED_DIRS or entry.startswith("."):
                continue
            subdir_node = build_tree(full_path, base_path, visited_paths)
            if subdir_node and subdir_node["children"]:
                node["children"].append(subdir_node)
        else:
            ext = os.path.splitext(entry)[1].lower()
            if entry.startswith(".") or ext in IGNORED_FILE_EXTENSIONS:
                continue
                
            symbols = parse_file(full_path)
            
            file_node = {
                "type": "file",
                "name": entry,
                "path": rel_path.replace(os.sep, "/")
            }
            if symbols:
                file_node["classes"] = symbols["classes"]
                file_node["functions"] = symbols["functions"]
                
            node["children"].append(file_node)
            
    return node


def render_markdown(node, indent=0, base_abs_path=""):
    """Recursively renders the directory tree into a Markdown list format."""
    lines = []
    space = "  " * indent
    
    if node["type"] == "directory":
        if indent == 0:
            lines.append("# Project Repository Map\n")
            lines.append(f"Root: `{node['name']}`\n")
            for child in node["children"]:
                lines.extend(render_markdown(child, indent + 1, base_abs_path))
        else:
            lines.append(f"{space}- 📂 **{node['name']}/**")
            for child in node["children"]:
                lines.extend(render_markdown(child, indent + 1, base_abs_path))
    else:
        abs_path = os.path.join(base_abs_path, node["path"]).replace(os.sep, "/")
        if not abs_path.startswith("/"):
            abs_path = "/" + abs_path
            
        file_link = f"[{node['name']}](file://{abs_path})"
        lines.append(f"{space}- 📄 {file_link}")
        
        file_space = "  " * (indent + 1)
        symbol_space = "  " * (indent + 2)
        
        # Render classes
        classes = node.get("classes", [])
        for c in classes:
            lines.append(f"{file_space}- 🏛️ **{c['name']}**")
            for m in c.get("methods", []):
                lines.append(f"{symbol_space}- `{m}`")
                
        # Render functions
        functions = node.get("functions", [])
        for f in functions:
            lines.append(f"{file_space}- `{f}`")
            
    return lines


def main():
    root_dir = os.path.abspath(os.getcwd())
    print(f"Scanning codebase at: {root_dir}")
    
    tree = build_tree(root_dir, root_dir)
    if not tree:
        print("Error: Could not scan the workspace root directory.")
        return
        
    # Write JSON map
    json_path = os.path.join(root_dir, "PROJECT_MAP.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(tree, f, indent=2)
    print(f"Generated JSON Map: {json_path}")
    
    # Write Markdown map
    markdown_lines = render_markdown(tree, base_abs_path=root_dir)
    markdown_path = os.path.join(root_dir, "PROJECT_MAP.md")
    with open(markdown_path, "w", encoding="utf-8") as f:
        f.write("\n".join(markdown_lines))
    print(f"Generated Markdown Map: {markdown_path}")
    
    print("\nDone! You can read the structured codebase layout in PROJECT_MAP.md or PROJECT_MAP.json.")


if __name__ == "__main__":
    main()
