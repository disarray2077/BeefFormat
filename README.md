# BeefFormat

A command-line source formatter and syntax tidier for [Beef](https://www.beeflang.org/).

## Usage

Checking (`--check`/`-c`) is the default. Use `--diff` (`-d`) to preview changes or `--write` (`-w`)
to apply them

```sh
BeefFormat src
BeefFormat -d "src/*.bf"
BeefFormat -w src
BeefFormat -h
```

Directory targets recurse through `.bf` files, while quoted filename patterns
select files in one directory. Add `--include-tests` to include `Tests` directories.

## Formatting rules

> [!WARNING]
> At its current stage, BeefFormat is strictly opinionated and applies all formatting rules unconditionally. It does not yet support configuration files, command-line toggles, or pragmas, though customization will likely be added in future updates if necessity arises.

### BF001 · Block layout

Expand block bodies onto separate lines.

```diff
-int Count() { return mCount; }
+int Count()
+{
+    return mCount;
+}
```

> [!NOTE]
> A `defer` block containing one simple statement retains its existing layout.

### BF002 · Void methods

Give explicitly `void` methods a block body.

```diff
-void Reset() => mCount = 0;
+void Reset()
+{
+    mCount = 0;
+}
```

### BF003 · Expression-bodied methods

Move nontrivial expressions below the signature when using the bind syntax.

```diff
 int Count() => mCount;
-int Sum() => left + right;
+int Sum()
+    => left + right;
```

> [!NOTE]
> Simple values and member references stay inline.

### BF004 · Nested control flow

Brace a control body that contains another control statement.

```diff
 while (running)
-    if (ready) Tick();
-    else if (pending) Retry();
+{
+    if (ready)
+        Tick();
+    else if (pending)
+        Retry();
+}
```

> [!NOTE]
> `else if` chains stay together.

### BF005 · Blank lines

Remove blank lines against block braces and collapse consecutive blank lines to one.

```diff
 void Update()
 {
-
     Tick();
 
-
-
     Tock();
-
 }
```

### BF006 · Properties and accessors

Keep expression-bodied properties and accessors on one line.

```diff
-int Count
-    => mCount;
+int Count => mCount;
 int Value
 {
-    get
-        => mValue;
+    get => mValue;
-    set
-        => mValue = value;
+    set => mValue = value;
 }
```

### BF007 · Unbraced bodies

Put unbraced control bodies on the next indented line.

```diff
-if (ready) Tick();
+if (ready)
+    Tick();
 defer Release();
```

> [!NOTE]
> Expression defers stay inline.

### BF008 · Switch sections

Place section statements below their labels, indented one level deeper.

```diff
 switch (kind)
 {
-case 0: Tick();
+case 0:
+    Tick();
 }
```

### BF009 · Member spacing

Separate fields from methods and add spacing around block-bodied methods and types.

```diff
 int mCount;
+
 void Reset()
 {
     mCount = 0;
 }
+
 struct Nested : this(int Value);
+
 int Count => mCount;
 int GetCount() => mCount;
 int this[int index] => index;
```

> [!NOTE]
> Expression-bodied methods, properties and indexers can stay together.

### BF010 · Primary-constructor structs

Replace an empty primary-constructor struct body with a semicolon when it contains no comments.

```diff
-struct Size : this(int Width, int Height) {}
+struct Size : this(int Width, int Height);
```

### BF011 · Indentation

Keep identation consistent, using one tab per level.

```diff
 void Update()
 {
     if (ready)
         Tick();
-        Tock();
+    Tock();
 }
```

### BF012 · Enums

Expand simple enum lists to one entry per line.

```diff
-enum Anchor { None = 0, Top = 1, Left = 2 }
+enum Anchor
+{
+    None = 0,
+    Top = 1,
+    Left = 2
+}
```