### ARFaceGeometry

- we add an additional texureCoordinate element to the geometry
- this enables us to support geometry warping without having to override SceneKit’s rendering system
 - the second textureCoordinate element is designed to work with Daz3D face textures

### SCNScene Info

#### face
- special node names
    - lut
        - if this node's material has a diffuse texture, that texture will be used to color the face node 
    - eyeLeft
        - eye tracking will be enabled if this node is present
        - the first material of this node will be used as the left eye's material
    - eyeRight
        - eye tracking will be enabled if this node is present
        - the first material of this node will be used as the right eye's material
    - geometry
        - this node's materials are applied to the ARFaceGeometry
        - custom modifiers are applied to the ARFaceGeometry 

#### world
- child nodes are placed into the scene and are fixed relative to the camera
- special node names
    - lut
        - if this node's material has a diffuse texture, that texture will be used to color all nodes in the scene 
    - overlay
        - if this node has a material name with `*.sks` or `*.plist` than an SpriteKit scene will be created and the scene's `overlaySKScene` property will be set to this SpriteKit scene

- lights
    - constraints are preserved (i.e. lookAt)

#### overlay 
> <small>*this name should be changed to mask* to avoid confusion</small>
- all child nodes will be attached to the face geometry
- special node names
    - lut
        - if this node's material has a diffuse texture, that texture will be used to color the mask node 


#### camera
- if a camera is present, use the color grading values for saturation and contrast, these are used by the colorProcessing pipeline

> *All lut textures are assumed to be 256x16 RGB images

### Special Material Names

- *.mp4
    - if a material has this name, an `AVPlayer` will be created and the media file with the material's name will be loaded into it
    - playback will be looped
    - the node will use the `AVPlayer` as it's diffuse material property

- *.sks
    - if a material has this name, a `SKScene` will be loaded using the material's name as the file name
    - the node will use the `SKScene` as it's diffuse material property

- *.plist
    - if a material has this name, an `AnimatedSpriteNode` will be created using the material's name as the file name
    - it is assumed the format of this file matches that of that exported by the `TexturePacker` application when using `plist` mode
    - the node will use the `AnimatedSpriteNode` as it's diffuse material property
    - `AnimatedSpriteNode` inherits from `SKSpriteNode` but is extended to support `TexturePacker`'s capabiltities

 
### Custom Material Properties

- cameraTexture
    - If this custom property is present, the renderer will set this texture with the output of the camera every render pass

- displacementMap
    - When present:
        - the contents of the materials's `SCNShaderModifierEntryPoint` is set to the contents of `displacementGeometryModifier.txt` file
        - the `SCNGeometryModifierEntryPoint` modifier is set from the contents of the  `displacementShaderModifier.txt` file
    - The texture must be an [OpenEXR](http://www.openexr.com/) image
    - Values are interpreted as follows:
        - R: x displacement
        - G: y displacement
        - B: z displacement
        - values = 0.5 have 0 displacement
        - values < 0.5 have negative displacement 
        - values > 0.5 have positive displacement

- backgroundInfluence
    - determines the amount if influence the camera texture has on the diffuse texture
    - default is 1.2

- backgroundAverage
    - determines the average background luminance used when blending with the camera texture
    - default is 0.5