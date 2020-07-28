# Character Animation

As I read this book, I summarize what I think is wrong. If you think my comments are wrong then please let me know. We can dicuss more and update your opinion.

## 1. Calculate the wrong world normal vector.

Calculate the world normal like below in CharacterShaders.metal.

```metal
out.worldNormal = uniforms.normalMatrix *
                  (skinMatrix * float4(vertexIn.normal, 1)).xyz;
```

It's wrong because the normal is not point. It is direction. In homogeneous coordinate if the value of w component is it means that this vector is point and if the value of w component is zero it means that this vector is direction. Thus it should be fixed like below.

```metal
out.worldNormal = uniforms.normalMatrix *
                  (skinMatrix * float4(vertexIn.normal, 0)).xyz;
```

## 2. Calculate the wrong model matrix.

Calculate the model matrix like below in Character.swift.

```swift
uniforms.modelMatrix = modelMatrix
```

It's wrong because this model matrix is coming from Node's model matrix. We need to multiply GLTF Node's model matrix. Thus it should be fixed like below.

```swift
uniforms.modelMatrix = modelMatrix * node.globalTransform
```

Because We need to cancle the global transform of GLTF's node not Node's transform. Thus we still need to muliply Node's transformation.
