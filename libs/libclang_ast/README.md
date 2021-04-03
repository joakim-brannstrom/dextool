The tool to generate the ast is `generate_clang_ast_nodes.d`. It is
specifically written to generate the AST thus if new node categories need to be
added the source code has to be changed.

The generator reads `libs/libclang_ast/source/libclang_ast/ast/nodes.d` to
understand what the node categories are and what nodes to generate.
`CXCursorKind` has to be manually analyzed and categoriesed.

```sh
cd tool
dub run
```
