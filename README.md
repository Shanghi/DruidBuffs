# DruidBuffs

###### Scary warning: Most of these addons were made long ago during Feenix days, then a lot was changed/added to prepare for Corecraft. Since it died, they still haven't been extensively tested on modern servers.

### [Downloads](https://github.com/Shanghi/DruidBuffs/releases)

***

## Purpose:
This shows some text like "Pyralis: Mark of the Wild" (moveable when holding shift) if you or your group needs a druid buff. You can set a key binding in the normal options to cast the missing buffs easily (this only works out of combat).

| Commands | Description |
| --- | --- |
| /buff thorns <"on"\|"off">                             | _enable or disable checking for Thorns_ |
| /buff thorns \<name>                                   | _toggle checking for Thorns on \<name>_ |
| /buff&nbsp;rebuff&nbsp;<"mark"\|"omen"\|"thorns">&nbsp;<minutes&nbsp;left> | _set when to rebuff each thing - setting to 0 would wait until it's fully off_ |
| /buff gift <group amount\|"off">                       | _use Gift of the Wild instead of Mark of the Wild if this many people need it_ |
| /buff color                                            | _pick the text's color_ |

## Screenshot:
![!](https://i.imgur.com/GhkVLVz.jpg)

## Notes:
* The text will be hidden in sanctuary areas like Shattrath, but you can still use the keybinding to buff people.
* Thorns will only be checked for people on the Thorns list. To check someone's pet, add `-Pet` to their name, like: **`/buff thorns Pyralis-Pet`**
* The buff priority is: Omen of Clarity, then Mark of the Wild, then Thorns. The target priority is: you, then group members, then pets.
