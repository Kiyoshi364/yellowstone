# Yellowstone

A Minecraft's Redstone inspired simulation
written in [zig](https://ziglang.org).

### Meta

Note that `---` are optmized for [slides](https://github.com/maaslalani/slides)

# How to run

* Run:
  ```console
  zig build run
  ```

* Build (executable is `zig-out/bin/yellowstone`):
  ```console
  zig build
  ```

* Run all tests:
  ```console
  zig build test
  ```

## Zig Caveats

### Zig Compiler Version

Note that zig is not released yet.

This project is being developed with the following `zig version`:
```console
$ zig version
0.11.0-dev.2160+49d37e2d1
```

Grabing from master or version `0.11.*` should work.
If not, following compiler errors shouldn't be hard.

See: ([downloads page](https:ziglang.org/download))

---
# Using the Simulation

## Available blocks

|Name|Char|Redstone Analog|Explanation|Extra info|
|----|----|---------------|-----------|----------|
|Empty|`' '`|"Air"|Empty space, does nothing|-|
|Source|`'S'`|Redstone block|Distributes powers to adjacent tiles|-|
|Wire|`'w'`|Redstone dust|Transport power to adjacent tiles|Always "broadcasts" power|
|Block|`'B'`|Any Solid Block|Can be powered, limits power transportation|-|
|Repeater|`'r'`|Repeater|Extends power transportation|Cannot be "locked"|
|Negator|`'n'`|Redstone Torch|Negates power|-|

---
## Terminal Rendering

Each tile is rendered as a 3x3 text (ignoring tile boundaries).
Some tiles examples:
```console
+---+---+---+---+---+---+---+
|   |   |   |  x|   |   | ^ |
|   | S | w | w | B | r>| n |
|   |*  |f  |e  |1  |1 1|1  |
+---+---+---+---+---+---+---+
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
* `c`: marks where the cursor is (one of " x")
* `b`: which block is there
* `p`: current power (one of " 12456789abcdef*")
  * `*` means that it is a source
  * for Repeater is its memory (related to delay)
  * for Negator is input that was read
* `i`: information
  * for Repeater is its delay (one of "1234")


---
# Interactive Controls

|Char|Action|
|----|------|
|`' '`|step|
|`'\r'`, `'\n'`|put selected block and step|
|`'w'`|move cursor up|
|`'s'`|move cursor down|
|`'a'`|move cursor left|
|`'d'`|move cursor right|
|`'z'`|move cursor above|
|`'x'`|move cursor below|
|`'H'`|retract camera left|
|`'J'`|expand camera down|
|`'K'`|retract camera up|
|`'L'`|expand camera right|
|`'n'`|select next block|
|`'p'`|select prev block|
|`'.'`|next rotate selected block|
|`','`|prev rotate selected block|
|`'q'`|exit program|

> _Note:_
> There are unmaped Actions like: 'expand camera left'.
> Maybe there will be some kind of config file to (re)map Actions.

---
# About the Simulation

## It Is NOT Redstone

Despite having some similarities with Redstone,
there are a couple of things
that doesn't make sense "to copy" from.
Most of them are related to interactivity with a player.
For example:
 - Buttons, Pressure plates, ...
 - Minecarts related things
 - Hopper
 - Storage stuff (things that Comparators might read)

Besides that, the goal of this project is **NOT**
to simulate Redstone.

Also, there are some design decisions
that I wouldn't like to give up on
(they will be listed in the following H2 heading).

---
## Design Decisions

Here goes some things that I'd not like to give up on.
(The order is not relevant, numbers are for reference)

### (1) Axis/Position Invariance

The ideia is that translating (moving), reflecting or rotating
the entire circuit 90 degrees in an arbitrary axis
(clock or counter-clock wise)
should keep the circuits behavior, i.e, not break it.

Other way of stating that is to say:
"No axis is special and no position is special".
In Minecraft the Z-axis is a special-one.
There is an implicit notion of gravity,
"things" ("non-block-like" blocks)
have to be on top of a block
(Redstone dust and repeaters, for example).

Redstone signals have a hard time to go up or down,
many circuits have to be redesigned
to be in a vertical configuration.

That may be a fun property for some,
but adds (unecessary) complexity.
I want the simulation to be "simple, yet powerfull".

About translation,
I'm unaware of Redstone being position sensitive.
The _Update Order_ might say otherwise.
A example is in _Mario Maker (2)_,
the position `x = 9`
makes things behave in a have a different way.
[Reference video](https://youtu.be/Xqq9iPeN4vU)

> _Note:_ **reflection** is not mentioned
> (here is a good place to say something about it!)

Also, it sounds like a "pretty property"
for the simulation to have;
it brings a notion of positional symmetry
to the simulation.

> _(Yes! At the end the important stuff is beauty!)_

---
### (2) Determinism

If the starting circuit state (configuration)
and sequence of inputs are the same,
all the deriving states (including the last one)
should be the same.

Besides sounds frustrating to a circuit
to work "sometimes" but not "othertimes",
it is a useful property to have:
* Not having this property sounds confusing
* A replay feature can save memory by storing only
  the initial state and the sequence of inputs.
* The simulation can be "screen casted" by sending inputs
  (a just like a live-replay!)
* There should be other reasons (but I don't remember :P)

For the record, I believe that Minecraft has this property
(but without any strong evidence about it).
Usually, if a simulation does not have it,
it is either a intetional thing or
someone messed something really hard

Also, just being deterministic is not enough,
it has to look deterministic:
I do not want to allow pseudo-random stuff.
The ideia is that this simulation should be
intuitive and simple.

---
### (3) No "Update Order" Complexity

Update Order is the notion of a simulation step
may lead to 2 or more different states based on
"what happens first".
If the Update Order is known before and clear enought,
"we" can simulate the next state before stepping the simulation.

Imagine the following grid, in a Redstone environment:
```
12
34
```
On tiles 1 and 4 there are pistons facing tile 2.
On tile 3 there is a button that, when pressed,
will power both pistons at the same time.
Once the button is pressed, what will happen?
The possibilities are:
1. Nothing (no piston will extend)
2. Only piston 1 will extend
3. Only piston 4 will extend
4. Both pistons will extend

I imagine that it's unituitive
for both pistons to remain retracted (1),
despite being a reasonable rule.

Both pistons extending (4), does not sound possible.
How will 2 piston-heads occupy the same tile?

Between (2) and (3), which piston will extend?
Maybe it is the piston 1,
because its "tile number" is "smaller".
Maybe it is the piston 4,
because it is to the "east" of the power source.
There may be a totally deterministic rule
to figure that out,
but when we simulate it in ours heads,
which will we use?

It boils down to a question of _priority_.
Which piston has higher priority?

---

In a general case,
I believe that priority rules
might come from the following places:
1. Absolute position
2. Relative position (where did the power came from)
3. Kind/Type of block
4. Throw of a dice

_Absolute position_ was the first idea,
that would lead to piston 1 extending.
It is a rule based on the "tile number"
that the block is on.

_Relative position_ was the next,
where piston 4 would extend.
It is a rule based on "time",
which is faster, which will happen first.
It is somehow connected to a notion of _chain reactions_.
"Power supply travels first to east, then to west ..."
kind of reasoning.

_Kind/Type of block_ was not pictured in the example.
The ideia is to say that a repeater "reacts faster"
then a comparator,
so the piston connected from a repeater will extend first,
comparing to another piston connected from a comparator.
A similar situation was if one of the pistons
were a stiky piston instead (let's say piston 4),
and this kind of piston is faster,
such that piston 4 would be extended.

_Throw of a dice_ relies on "randomness" to solve
the priority question,
that being actuall-real random or pseudo-random.

Those rules most likely come from "implementation details"
and are not immediately obvious to newcomers.

Arguably this entire section could be erased,
because they offend another design rule
(I'll not talk about it for now, it is already really big),
being the 3rd one (_Kind/Type of block_) the least offender.
The main reason it's there is to ease
the conflicting principles on how to introduce pistons,
currently I have no ideia how to make it work.
