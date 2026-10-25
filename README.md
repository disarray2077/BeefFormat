# BeefFormat

A standalone Beef console formatter using the sibling **BeefParser** project.
It applies source edits, never AST-generated source. Checking is the default.
The required BeefParser source-span/error API is committed through `cb2652f` in that
repository; keep that revision or a compatible newer revision beside BeefFormat.

```powershell
& 'C:\Program Files\BeefLang\bin\BeefBuild.exe' -workspace=D:\BeefLang\Repository\BeefFormat
.\build\Debug_Win64\BeefFormat\BeefFormat.exe --check path\to\Source.bf
.\build\Debug_Win64\BeefFormat\BeefFormat.exe --diff path\to\Source.bf
.\build\Debug_Win64\BeefFormat\BeefFormat.exe --write path\to\directory
```

At least one file or directory is required. Modes are mutually exclusive. Use
`--include-tests` to traverse `Tests`, and `--` before targets beginning with `-`.
Traversal sorts and deduplicates absolute file paths, searches for `*.bf`, and
excludes `Tests`, `build`, `dist`, `generated`, `bin`, `obj`, `BeefSpace`, `.git`,
`.svn`, `.hg`, and `recovery` directories. Build and Tests exclusions also apply to explicit
directory targets; explicitly named files are processed. Directory links found
while traversing are skipped, as are file links discovered during traversal.
Initial directory enumeration failures are processing errors. Check/diff never write. Diff emits a unified diff
with one whole-file hunk, including missing-final-newline markers.

Exit codes: **0** means no differences remain; **1** means check/diff found
fixable differences; **2** means usage or processing errors. Errors take
precedence across files. A failed file is never partially formatted. Successful
files may still be written when another target fails.

## Implemented policy and proofs

These are deliberately bounded syntax rules. A construct outside a rule's
preconditions has no finding for that rule. There are no uncertain findings or
subjective style diagnostics. Other applicable rules can still format its
whitespace. Tabs provide indentation; block lambdas are indented even when already
multiline. Expanding an inline body also indents its recognized nested statements.
Other existing multiline indentation is retained. The formatter does not infer logical phases or remove single blank
lines between statements.

| ID | Exact applicability and exclusions | Behavior preservation |
| --- | --- | --- |
| BF001 | Type/namespace bodies; recognized member method, constructor and destructor bodies; property bodies containing implemented accessors; recognized statement blocks and block lambdas, including field initializers and expression-bodied properties. Expand when either brace shares its line with its adjacent code token; normalize block lambdas even if already multiline. Put braces, body boundaries, and recognized consecutive declarations/statements on separate indented lines. Propagate indentation to recognized nested controls in the expanded body. An empty block has opening and closing braces on separate lines. A gap containing a comment or directive is preserved. | Replace whitespace gaps only. Tokens and protected source spans retain their original order and text. |
| BF002 | Ordinary methods whose first parameter list is immediately preceded by `void Identifier`, and whose complete expression body is `Identifier(arguments)`. Header-to-arrow and arrow-to-expression gaps must contain only whitespace. Exclude generic method names, qualified/mixin calls, constructors, operators, interpolated literals, and expressions containing `scope`, `new`, `delete`, `ref`, `out`, `=>`, or curly braces. | Explicit `void` makes the original call's result discarded. A method block containing the identical call and semicolon also discards that result, with the same evaluation and method scope. No return, allocation or binding is introduced. Original expression text, including argument comments, is copied verbatim. Compiler/run tests exercise both void-returning and value-returning calls. |
| BF003 | Existing expression-bodied members identified as methods by a parameter list before their arrow and outside field initializers. Move the arrow to the following line, indented one level beyond the declaration; separate the arrow and expression by a space. BF002 takes priority. Comment/directive gaps are excluded. | Whitespace only; expression and semicolon stay intact. |
| BF004 | An unbraced nested control tree consisting only of `if (true/false)`, `while (true/false)`, and `for (;;)`. Leaves are `return;`, `return integer/bool-literal;`, `break;`, or `continue;`. Both arms of each `if` must satisfy this grammar. The complete tree must contain no comments or directives. Wrap a control's body/else arm when that arm is another control. Existing braced trees and all other predicates, declarations, calls, labels, and lifetime-bearing statements are excluded. | Recursive descent consumes each `else` at its original nearest unmatched `if`. Inserted blocks contain no declarations, references, allocations, defers, or user-defined computations. They cannot change name lookup, local scope/lifetime, loop targets, or ownership. No statements or expressions are reordered. Tests compile/run dangling-else and nested-loop cases before/after. |
| BF005 | Pure whitespace immediately inside recognized block braces: remove all empty lines. Elsewhere, a whitespace trivia span with three or more line terminators is reduced to two, leaving at most one empty line. Existing structural edits take priority. | Never touches literal, comment, or directive spans. Retains original surviving terminators and final indentation. |
| BF006 | Existing expression-bodied properties and implemented accessors. Join the gap before the arrow and newline-bearing whitespace gaps through their terminating semicolon using spaces. Preserve gaps without newlines inside the expression. Exclude comment/directive gaps; a multiline literal itself is opaque and remains multiline. | Tokens, operators, and literals are unchanged; token separation remains present when joining a newline. |

Auto-property accessor lists (`{ get; private set; }`), enum bodies, and object
and array initializers are not expanded. Expression lambdas retain expression
form; block lambdas retain block form and use BF001. No lambda form conversion
is implemented. Local function blocks and expression blocks that are not one of
the recognized bodies currently retain their internal layout. These are rule
exclusions, rather than review findings.

## Analysis and preservation limits

* The optional `Lexer.GetSourceTokens` API returns a partition of original
  UTF-8 byte ranges, including trivia. It reuses the existing token lexer and
  consumes comments/directives before delegating token recognition. It handles
  nested block comments without changing the legacy token API. Interpolated
  strings are opaque ranges; formatting never enters an interpolation.
* Ordinary, verbatim, multiline, and simple interpolated literals are preserved
  verbatim. Nested interpolated literals and curly nesting inside interpolation
  are processing errors because the existing lexer cannot track them reliably.
  Syntax not accepted by the existing lexer/parser is a processing error.
* Before edits, BeefParser validates copies with comments, directives and inactive
  alternatives masked to equal-length whitespace. This avoids its legacy comment limitations. The
  parser's new `BreakOnError = false` opt-in returns errors without breaking the
  process; existing clients retain the original default.
* Conditional directives (`#if`, `#elif`, `#else`, `#endif`) are retained. Every
  syntactic alternative is parsed and formatted separately, without evaluating
  macro values. The results merge only when shared source edits agree. A malformed
  alternative rejects the entire file and clears all pending edits; alternatives
  cannot supply each other's missing syntax. Each branch must contain complete
  declarations/statements and maintain the delimiter depth present at `#if`.
  Independent/nested conditionals generate at most 256 syntax variants; exceeding
  that limit is a processing error before any write. Conditions are treated as
  independent, so correlated conditions that require semantic evaluation to make
  a variant valid remain outside the supported preprocessor subset.
  Conditions support macro identifiers, `true`, `false`, `!`, `&&`, `||`, and
  parentheses; conditions are syntax-checked and never evaluated. Other condition
  forms are unsupported. Unexpected tokens after `#else`/`#endif` are errors. Directives
  inside a statement/header, split-syntax branches, and unmatched conditionals
  are processing errors. `#region`, `#endregion`, `#unwarn`, `#warn`, and `#pragma`
  at syntax boundaries are preserved. Other directive names are errors. This is
  not a semantic compiler.
* Input supports strict UTF-8, with or without its original BOM, and BOM-marked
  UTF-16/UTF-32 in either byte order. Output retains its original encoding/BOM.
  Other encodings, NUL characters, invalid Unicode (including unpaired UTF-16
  surrogates), and nesting beyond 128 delimiters are rejected. Unicode identifiers
  are limited to what BeefParser accepts; Unicode
  comments and literals are preserved. Existing LF/CRLF/CR, mixed surviving line
  endings, and the presence/absence of a final newline are retained. Inserted
  lines use the nearest following line ending, otherwise the preceding one,
  otherwise LF.
* Edits are non-overlapping. Before any CLI write or difference report, the
  resulting source must parse and a second analysis must produce zero edits.
  Any conflict or failure is a processing error with no write to that file.

## Validation

```powershell
& 'C:\Program Files\BeefLang\bin\BeefBuild.exe' -workspace=D:\BeefLang\Repository\BeefFormat -test
.\Tests\Run-Integration.ps1
& 'C:\Program Files\BeefLang\bin\BeefBuild.exe' -workspace=D:\BeefLang\Repository\BeefParser -test
```

The Beef tests cover rules, exclusions, token/literal/comment preservation,
Unicode, nested comments, line endings, source ranges, directive alternatives,
malformed syntax, and idempotence. The integration script creates explicit
fixtures only under `%TEMP%`, tests CLI modes/exits, byte preservation and
exclusions, then compiles and executes a behavior fixture before and after
formatting. That fixture checks dangling-else binding, loop targets, call result
discard, side effects, and destruction of a surrounding scoped object. Temporary
fixtures are retained for inspection. No repository-wide formatting is performed.

Validated with the installed Beef compiler: Debug and Release builds, 20 formatter
tests, 133 integration assertions, and all 35 existing BeefParser tests passed.
