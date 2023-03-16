# Yellowstone

A Minecraft's Redstone inspired simulation
written in [zig](https://ziglang.org).

### Meta

Note that `---` are optmized for [slides](https://github.com/maaslalani/slides)

# How to run

* Run:
  ```console
  $ zig build run
  ```

* Build (executable is `zig-out/bin/yellowstone`):
  ```console
  $ zig build
  ```

* Run all tests:
  ```console
  $ zig build test
  ```

## Zig Compiler Version

Note that zig is not released yet.

This project is built using the following `zig version`:
```console
$ zig version
0.11.0-dev.1800+c7f479c3c
```

Grabing from master or version `0.11.*` should work.
If not, following compiler errors shouldn't be hard.

See: ([downloads page](https:ziglang.org/download))

---
# Simulation explanation

## Available blocks

|Name|Char|Redstone Analog|Explanation|Extra info|
|----|----|---------------|-----------|----------|
|Empty|`' '`|"Air"|Empty space, does nothing|-|
|Source|`'S'`|Redstone block|Distributes powers to adjacent tiles|-|
|Wire|`'w'`|Redstone dust|Transport power to adjacent tiles|Always "broadcasts" power|
|Block|`'B'`|Any Solid Block|Can be powered, limits power transportation|-|
|Repeater|`'r'`|Repeater|Can be powered, limits power transportation|Cannot be "locked"|

---
## Terminal Rendering

Each tile is rendered as a 3x3 text (ignoring tile boundaries).
A tiles examples:
```console
+---+---+---+---+---+---+
|   |   |   |  x|   |   |
|   | S | w | w | B | r>|
|   |*  |f  |e  |1  |1 1|
+---+---+---+---+---+---+
```

A general tile is organized in this way:
```console
+---+
|ddc|
|dbd|
|pdi|
+---+
```
where:
* `d`: is a direction (one of " x^>v<o")
  * Note: `x` and `o` are reserved for 3D implementation,
  therefore unused
* `c`: marks where the cursor is (one of " x")
* `b`: which block is there
* `p`: current power (one of " 12456789abcdef*")
  * `*` means that it is a source
  * for Repeater is its memory (related to delay)
* `i`: information
  * for Repeater is its delay (one of "1234")


---
# Interactive Controls

|Char|Action|
|----|------|
|`' '`|step|
|`'\n'`|put selected block and step|
|`'w'`|move cursor up|
|`'s'`|move cursor down|
|`'a'`|move cursor left|
|`'d'`|move cursor right|
|`'n'`|select next block|
|`'p'`|select prev block|
|`'.'`|next rotate selected block|
|`','`|prev rotate selected block|
|`'q'`|exit program|

