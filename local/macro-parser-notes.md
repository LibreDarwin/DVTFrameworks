# Macro expression parser — RE notes (Apple DVTMacroFoundation, build 24904)

Probe: /tmp/parse_probe.m against Apple's DVTMacroFoundation.  It calls
`-[DVTMacroDefinitionTable parseAndSetValue:forMacroName:conditionSet:]`
and dumps the stored value (`dvt_isLiteral`, `dvt_stringForm`,
`dvt_debugDescription`, list elements, `dictionaryRepresentation`).

## Shape

- Parsing a *string* always yields `DVTMacroExpansionStringList_NonLiteral`
  (lit=0), even when the string contains no `$(`.
  - `"plain"` -> list with one plain `NSString` element "plain".
  - `"a b c"` -> three plain `NSString` elements a, b, c.
  - Empty string -> `DVTMacroExpansionStringList_Literal` (lit=1), count 0.
- Elements are produced by shell-like word splitting on whitespace; a
  `$(...)` group stays inside one word.
- A word with no `$(` is a plain `NSString` (often NSTaggedPointerString),
  whose `dvt_debugDescription` is `【%@】`.
- `$(FOO)` -> one `DVTMacroExpansionString_Substitution` element,
  `dvt_stringForm` `$(FOO)`.
- `a$(FOO)b` and `$$(FOO)` -> one `DVTMacroExpansionString_Concatenation`
  element; `$$(FOO)` splits into `【$】` + `【𝗦𝘂𝗯𝘀𝘁𝗶𝘁𝘂𝘁𝗶𝗼𝗻:【FOO】】`.
- Nested `$( )`: the macro-name expression is itself an expansion string:
  `$(if $(X),y,z)` -> Substitution whose name expression is
  `【𝗖𝗼𝗻𝗰𝗮𝘁𝗲𝗻𝗮𝘁𝗶𝗼𝗻:【if 】✚【𝗦𝘁𝗿𝗶𝗻𝗴𝗦𝘂𝗯𝘀𝘁𝗶𝘁𝘂𝘁𝗶𝗼𝗻:【X】】✚【,y,z】】`
  (`DVTMacroExpansionString_StringSubstitution`, not `_Substitution`).
- `dvt_stringForm` of the list is the whitespace-joined element forms; it
  reproduces the input for single-element inputs (quotes in
  `dictionaryRepresentation` come from the plist writer).

## Debug descriptions

- list: `【𝗡𝗼𝗻𝗹𝗶𝘁𝗲𝗿𝗮𝗹𝗔𝗿𝗿𝗮𝘆:<e1>,<e2>】`, rsp. `【𝗟𝗶𝘁𝗲𝗿𝗮𝗹𝗔𝗿𝗿𝗮𝘆:<e1>,...】`
- concatenation: `【𝗖𝗼𝗻𝗰𝗮𝘁𝗲𝗻𝗮𝘁𝗶𝗼𝗻:【a】✚【𝗦𝘂𝗯𝘀𝘁𝗶𝘁𝘂𝘁𝗶𝗼𝗻:【FOO】】✚【b】】`
- substitution: `【𝗦𝘂𝗯𝘀𝘁𝗶𝘁𝘂𝘁𝗶𝗼𝗻:【FOO】】`, with operators appended as
  `:【𝗹𝗼𝘄𝗲𝗿】` (non-bold operator text, raw argument included, e.g.
  `【𝘀𝘂𝗳𝗳𝗶𝘅=_d】`, `【𝗿𝗲𝗹𝗮𝘁𝗶𝘃𝗲𝘁𝗼=/a】`).
- operators that failed to parse/are unknown: `:【<𝗘𝗥𝗥𝗢𝗥>】`.
- `xml` is NOT registered in this build (`:xml` -> `<𝗘𝗥𝗥𝗢𝗥>`), while
  `quote`, `upper`, `lower`, `file`, `dir`, `identifier`,
  `rfc1034identifier`, `c99extidentifier`, `standardizepath`, `suffix`,
  `base`, `relativeto` are (base and relativeto parse even though headers
  call them replacement operators).

## Entry points and the `flag` that differs (verified)

- `DVTMacroExpressionByParsingString` calls the C parser with `flag = YES`;
  `DVTMacroExpressionByParsingStringAsList` / `...ArrayAsList` call it with
  `flag = NO`.  The flag selects
  `DVTMacroExpansionString_StringSubstitution` (YES) vs
  `DVTMacroExpansionString_Substitution` (NO), and is passed down into nested
  `$(...)` name/operator-argument parses.
- `DVTMacroExpressionByParsingString` short-circuits `""`/`"NO"`/`"YES"`,
  the `\x01$(inherited)` marker, and strings with no `$`.
- AsList splits on unquoted whitespace, honours `\` escapes and `"`/`'`
  quoting, and wraps the parts in `DVTMacroExpansionStringList_NonLiteral`.
  `""` is the shared zero-element literal list.
- ArrayAsList parses each array element as one word using its file-system
  representation, then joins the elements with `" "` to build the list's
  `dvt_stringForm`.  Apple aborts on non-string array members (it sends
  `_fastCStringContents:` to every element); we raise
  `NSInvalidArgumentException` instead (documented deviation).

## Bare-name `$(...)` grouping (verified from the disassembly)

After a bare `$name` (letters/digits/`_`/`.`), exactly one immediately
following `$(` is parsed recursively into the same name expression:

    $x$(F)        -> one Substitution, name = Concatenation【x】✚【Substitution F】
    $x$(F)$(G)    -> Substitution($x$(F)) followed by top-level $(G)
    $x$y, $x$1    -> not grouped
    $x${F}, $x$[F]-> not grouped (only an opening parenthesis triggers this)

The name expression is always a `Concatenation`, even with one part, and its
original string runs from the identifier start through the nested group.

## `$` fallback (verified)

A `$` that does not start `(`, `{`, `[`, a letter or `_` is a literal:
`$$` -> `"$"`, `$1` -> Concatenation【$】✚【1】, `$$(F)` -> Concatenation
【$】✚Substitution(F).  List mode additionally treats `$$` as a literal `$`
inside a word.

## Expression validation

Apple's own parser produces plain `NSString` fragments for names and
arguments (often tagged pointers), not protocol-conforming objects.  All
initializers therefore check `isKindOfClass:[NSString class]` or
`DVTMacroExpansion`, never `conformsToProtocol:` alone.

## `DVTMacroDefinitionTable` initialisation

The header declares `- (id)init;`, and the implementation must override it as
`return [self initWithLabel:nil];`.  Without that override `+new` leaves the
map table and cache lock nil, so `setValue:` silently stores nothing.

## Debug descriptions

- list: `【𝗡𝗼𝗻𝗹𝗶𝘁𝗲𝗿𝗮𝗹𝗔𝗿𝗿𝗮𝘆:<e1>,<e2>】` / `【𝗟𝗶𝘁𝗲𝗿𝗮𝗹𝗔𝗿𝗿𝗮𝘆:...】`
- concatenation: `【𝗖𝗼𝗻𝗰𝗮𝘁𝗲𝗻𝗮𝘁𝗶𝗼𝗻:【a】✚【...】】`
- substitution: `【𝗦𝘂𝗯𝘀𝘁𝗶𝘁𝘂𝘁𝗶𝗼𝗻:...】`; string form:
  `【𝗦𝘁𝗿𝗶𝗻𝗴𝗦𝘂𝗯𝘀𝘁𝗶𝘁𝘂𝘁𝗶𝗼𝗻:...】`; operators append `:【<op>】`
  (replacement arguments as `【op=arg】`), parse failures as `【<ERROR>】`.
- Italic headings use U+1D5D4/U+1D5EE ranges, so they must be emitted as
  UTF-32 (surrogate pairs); `%C` with a 16-bit `unichar` corrupts them.

## Status

All of the above is implemented in `DVTMacroExpressionParser.m` and the
`DVTMacroExpansionString*` classes.  `/tmp/parse_probe{,4}` are byte-identical
to Apple.  The only remaining probe differences are Apple's own crashes on
non-string array input and the tail it never prints.
