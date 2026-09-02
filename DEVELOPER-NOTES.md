# Character model

The character model is made with Blender (`.blend`) and exported to the glTF binary format (`.glb`).
It uses multi-track animations, which means we can play multiple tracks simultaneously, each setting a different set of bones.
This feature is only properly supported since Luanti 5.17.

## Rotation modes

Each bone must have exactly one rotation mode throughout the file, otherwise some animations will not be displayed properly.
We use the XYZ Euler mode for all bones.
It is known to have the "gimbal lock" problem, but is more intuitive for editing.

## Exporting glb

We export `.glb` files from the Blender menu "File" -> "Export" -> "glTF 2.0 (.glb/.gltf)".
Some options (in the right sidebar of the export dialog) must be set properly:

-   "Animation Mode" must be "Actions".
    Otherwise, some single-frame animations will be excluded from the exported `.glb`.
-   "Optimize Animations" -> "Force Keeping Channels for Bones" must be **off**!
    Otherwise, all animations will include all bones, making it impossible, for example, for the mining animation to override the right arm movement, only.

Note that exporting may take a few seconds, depending on the machine.
Please make sure Blender has finished exporting before you test the exported model in Luanti.
