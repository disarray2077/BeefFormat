# BeefFormat

A standalone Beef console formatter using the sibling **BeefParser** project.
It applies source edits, never AST-generated source. Checking is the default.
Lossless source-token support lives in this project's `src/SourceTokens` folder:
`SourceToken.bf` defines `BeefFormat.SourceTokens.SourceToken`, and
`SourceTokenLexer.bf` extends the sibling lexer from BeefFormat. The extension uses
the `BeefParser` namespace to attach to `Lexer`, but is compiled by BeefFormat.
BeefParser provides lexical recognition and its opt-in quiet-error API.
This checkout additionally uses BeefParser's `append` field-modifier and
`MethodBindingExpr` support for method references such as `=> WindowProc`.
It also supports struct primary constructors (`struct S : this(int X) {}`)
and property finalizers (`{ get; set; } ~ _.Dispose();`). Property finalizers
remain part of their property declaration; they do not count as a field group
for BF009. Block finalizers use the ordinary block formatting rules.
Supported syntax also includes named call arguments, namespace-level `static`
blocks, extension-method `this` parameters, `function` declarations, delegate
fields, `implicit void operator+=`/`operator-=` declarations, property initializers,
allocated method references (`new => Handler`), allocator mixins with inferred
arrays (`new:ScopedAlloc! .[count]`), and lambda capture lists with default or
named value/reference captures. Initialized captures and explicitly typed lambda
parameters remain unsupported. Escaped character literals may represent UTF-16
surrogate code units; their original spelling is preserved. Raw source encodings
must still be valid Unicode. Decimal reals may contain digit separators.

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
with three lines of context, accurate old/new line ranges, and separate hunks for
distant changes. Nearby hunks merge; unchanged lines are prefixed with a space,
removals with `-`, and additions with `+`. Missing-final-newline markers are included.
Line matching uses Myers' shortest edit path, with deterministic tie breaking.
For changes exceeding 2,048 inserted/deleted lines, trace memory is bounded by
falling back to a replacement between the common leading and trailing lines.

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
Recognized declaration/statement starts, implemented accessor headers and block
braces use one tab per syntax level even in existing multiline blocks. Expression
continuations and comment-only lines retain their existing indentation. The formatter does not infer logical phases or remove single blank
lines between statements.

| ID | Exact applicability and exclusions | Behavior preservation |
| --- | --- | --- |
| BF001 | Type/namespace bodies; recognized member method, constructor and destructor bodies; property bodies containing implemented accessors; recognized statement blocks and block lambdas, including field initializers and expression-bodied properties. Expand when either brace shares its line with its adjacent code token; normalize block lambdas even if already multiline. Put braces, body boundaries, and recognized consecutive declarations/statements on separate indented lines. Propagate indentation to recognized nested controls in the expanded body. An empty block has opening and closing braces on separate lines. A gap containing a comment or directive is preserved. A defer block containing exactly one simple semicolon-terminated statement retains its existing layout; exclude nested control statements and additional top-level semicolons from that exemption. | Replace whitespace gaps only. Tokens and protected source spans retain their original order and text. |
| BF002 | Every supported method with an explicit void return type and an expression body, including generic names, explicit-interface implementations and local methods. Replace the arrow with an opening method brace and add a closing brace after the existing expression statement; preserve comments around the arrow and trailing semicolon. No restriction to call syntax: assignments, compound assignments, increments, qualified/generic/null-conditional calls, allocations, callback assignments and nested lambdas all use this rule. Exclude pointer/function return types, constructors/destructors, aliases and generic return types whose void specialization cannot be established syntactically. Unsupported syntax remains a processing error without writes. Takes priority over BF003. | Beef checks an explicitly void expression body with the same statement-validity check as an expression statement. Both forms discard the expression result in the same method body scope. The original expression tokens and semicolon remain unchanged; nested lambda whitespace may be formatted separately. Compiler/run tests cover assignments, compound assignments, prefix/postfix increments, generic/qualified/null-conditional calls, local methods, value-result discard and scoped-argument destruction. |
| BF003 | Existing expression-bodied methods. A single identifier, dotted identifier chain, or single-line numeric/string/character/bool/null literal stays inline; join whitespace-only expression gaps. Other expressions put the arrow on the next indented line. Calls, casts, indexing, operators, multiline literals and commented expressions are excluded from the simple subset. BF002 takes priority; comment/directive gaps remain untouched. | Whitespace only; expression tokens and semicolon stay intact. |
| BF004 | Structurally wrap an unbraced control body when that body is another parsed control statement: if, while, for (including foreach), using, switch, repeat, do, or defer. Keep else-if arms combined. Conditions and leaves are unrestricted within supported parser syntax. Close after the complete inner statement, including its else arms or repeat continuation. Exclude wraps crossing directives/inactive source; preserve comment bytes. | Explicit braces represent the control body scope already supplied by Beef for an unbraced statement. Parsing consumes each else at its original nearest unmatched if. Existing statements, labels within bodies, loop targets, allocations and defers stay inside their original control body. Compiler/run tests cover nonconstant predicates, pattern bindings, dangling else, loop targets, scope:: destruction and defer:: execution. |
| BF005 | Pure whitespace immediately inside recognized block braces: remove all empty lines. Elsewhere, a whitespace trivia span with three or more line terminators is reduced to two, leaving at most one empty line. Existing rule-specific edits take priority. | Never touches literal, comment, or directive spans. Retains original surviving terminators and final indentation. |
| BF006 | Existing expression-bodied properties and implemented accessors. Join the gap before the arrow and newline-bearing whitespace gaps through their terminating semicolon using spaces. Preserve gaps without newlines inside the expression. Exclude comment/directive gaps; a multiline literal itself is opaque and remains multiline. | Tokens, operators, and literals are unchanged; token separation remains present when joining a newline. |
| BF007 | Every recognized unbraced `if`/`else`, `while`, `for` (including foreach-form `for`), `using`, `repeat`, and `do` body starts on the next line, indented one tab level beyond its header. This applies in existing multiline blocks, block lambdas and recognized block local functions. Keep `else if` as one header at the same indentation level; join whitespace-only gaps with one space and indent its body once. Do not join across comments or directives. Align `else` and repeat's trailing `while` with their controlling headers. Expression defers, including `defer::` and `defer:mixin`, stay inline: join whitespace-only header/body gaps and expression line breaks with one space. Preserve comment/directive gaps and literal bytes; when the expression contains braces, retain internal layout and format block lambdas normally. Defer bodies containing control statements retain the control-flow rules. BF004 takes priority when its brace-insertion grammar applies. Intervening comments remain in place; replace only trailing whitespace after the final comment. A gap containing directives or inactive source code is excluded. | Only whitespace around parsed bodies/continuation keywords and between defer expression tokens changes. No braces, expressions, semicolons, or statements are added, removed, or reordered; binding, scope, lifetime, and ownership remain intact. |
| BF008 | Visit switch sections separately from ordinary statement blocks. Place `case`/`default` labels on lines aligned with the switch header, then place every section statement on its own line one tab level deeper. Skip balanced expression delimiters and distinguish ternary colons when finding the label separator. Empty/stacked labels stay empty; existing case blocks and nested switches are visited without introducing scopes. Comments are preserved using the same trailing-whitespace rule as BF007. Directive/inactive-code gaps are excluded. | Whitespace only. Label values, separators, section boundaries, implicit section-exit behavior, variable lifetimes, and control-flow targets remain unchanged. No fallthrough or implicit statement is introduced. |
| BF009 | Insert exactly one blank line at declaration boundaries: field group to following callable; either side of a constructor/destructor; between adjacent methods when either has a block body, including BF002 output; and either side of class/struct/interface/extension/enum/typealias/recognized delegate declarations. Applies in member or namespace lists as appropriate, never against enclosing braces or between local statements. Separate methods from adjacent fields, properties and indexers on either side, except when both members are expression-bodied methods, properties or indexers. Use the final body form: BF002 void-method blocks do not qualify. Expression complexity and continuation-line placement do not affect this exception. Keep consecutive fields and expression-bodied member groups together; existing single blank lines may remain. Exempt consecutive typealiases, consecutive named delegates and consecutive named function types from type separation; different categories still separate. Preserve trailing/leading comment attachment and attributes; exclude directive/inactive-code gaps. Takes priority over BF001/BF005. | Separating whitespace only; declaration order, scopes, attributes and initializers remain unchanged. |
| BF010 | Empty struct with a primary constructor, with only whitespace between its final header token and opening brace and between braces. Replace that whitespace and the two braces with a semicolon. Preserve commented/nonempty bodies and ordinary empty structs. | Both Beef forms declare the same primary constructor and generated fields with no additional members. Before/after compiler/run tests check constructed field values. |
| BF011 | For parsed declaration headers, implemented accessor headers, statement starts and recognized block braces that are the first code token on their source line, replace only their leading spaces/tabs with one tab per syntax level. Preserve blank lines, line endings, comment-only lines, directives, literal contents and expression continuations. Auto-property lists, simple enum interiors and initializer interiors retain their existing layout. Indentation composes with higher-priority layout replacements rather than creating overlapping edits; single-statement defer blocks keep their existing line layout. | Whitespace only. Depth comes from the statement/declaration structure; an over-indented sibling stays a sibling. No braces or other syntax tokens are introduced by this rule. Compiler/run tests check both paths of the misleading-indentation example. |

Auto-property accessor lists (`{ get; private set; }`), simple enum case-list bodies, and object
and array initializers are not expanded. Expression lambdas retain expression
form; block lambdas retain block form and use BF001. No lambda form conversion
is implemented. Block and expression-bodied local methods are visited for the same method/body
rules as member methods. Other expression blocks retain their internal layout
unless an existing rule explicitly recognizes them. These are rule
exclusions, rather than review findings.
Verbose enums containing `case` declarations and ordinary members use the same
declaration, property and statement rules as other type bodies. Generic method
headers are recognized by their closing `>` token; generic constructors also
retain constructor-specific member separation.

## Analysis and preservation limits

* Source-token and line-ending positions use binary-search indexes. Edit starts
  and queued closing braces use hash indexes for duplicate/merge lookup; sorted
  validation passes reject overlaps. Blank-line cleanup checks the sorted edit
  prefix instead of scanning all edits for every whitespace span.
* BeefFormat's `Lexer.GetSourceTokens` extension returns a partition of original
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
.\Tests\Run-Integration.ps1 -RegressionFile path\to\Source.bf
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

An optional `-RegressionFile` accepts one or more explicit source files and copies each into the temporary
fixture directory and tests check/diff/write and idempotence there, verifying
that the original file remains unchanged. The behavior fixture also exercises
an append-allocated collection, an inferred method-reference callback, struct
primary-constructor values, automatic property-finalizer disposal, named arguments,
extension methods, property initializers, allocated callbacks, capture lists, and
escaped surrogate code units. The reported 14-file BeefForms regression list is
saved in `Tests/BeefFormsRegressionFiles.txt` and can be run explicitly:

```powershell
$files = Get-Content .\Tests\BeefFormsRegressionFiles.txt | ForEach-Object { Join-Path 'D:\BeefLang\BeefForms' $_ }
.\Tests\Run-Integration.ps1 -RegressionFile $files
```

Validated with the installed Beef compiler: Debug builds and 72 formatter
tests. Integration tests cover CLI behavior, source preservation, compiler/run
behavior comparisons and idempotence; optional BeefForms regressions use temporary
copies and verify that original files remain unchanged.

`Tests/Measure-Scaling.ps1` reports median formatting times for generated sources
of increasing sizes, using temporary files and checking idempotence. A Debug
comparison on the same 2,000-method input measured about 3.0 seconds before the
index changes and 0.13 seconds after; 4,000 methods took 0.22 seconds afterward.
These measurements include process startup and the CLI's validation pass.

Indentation was compared against the previous formatter on those 16 explicit
BeefForms files using temporary copies. Only `src/Helpers/ScopedArray.bf` gained
additional changes: four mixed tabs/spaces prefixes became three tabs. Original
files remained unchanged; all 16 formatted copies passed a clean second check.
