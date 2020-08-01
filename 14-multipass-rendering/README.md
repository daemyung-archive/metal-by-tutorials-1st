# Multipass & Deferred Rendering

As I read this book, I summarize what I think is wrong. If you think my comments are wrong then please let me know. We can dicuss more and update your opinion.

## 1. Need to pass the drawable size.

This example use view's bounds size as the drawable size in Renderer.swift but it's only right when the content scale is 1. Thus below code could make the crash.

```swift
mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)
```

If your system use HDPI then you system use the content scale which is bigger than 1. It can be 2 or 3 depends on your monitor's resolution. In a nutshell view's bounds size can be different from the drawable size when the content scale is not 1. For example the content scale is 2 and view's bounds size is 512x512 then the drawable size would be 1024x1024. Thus it should be fixed like below.

```swift
mtkView(metalView, drawableSizeWillChange: metalView.drawableSize)
```


## 2. Create the wrong world normal vector.

Create the world normal like below in Gbuffer.metal.

```msl
out.normal = float4(normalize(in.worldNormal), 1.0);
```

It's wrong because the normal is not point. It is direction. In homogeneous coordinate if the value of w component is it means that this vector is point and if the value of w component is zero it means that this vector is direction. Thus it should be fixed like below.

```msl
out.normal = float4(normalize(in.worldNormal), 0.0);
```

Actually this changes doesn't make any different but we must take care of it.

## 3. Calculate the position in world space at the composition pass.

This example uses one texture to save the position in the world space. We can calculate the position in the composition pass so we don't have to save the position to a texture. If we know an inverse projection matrix, an invertex view matrix and the depth in the clip space then we can calculate the position in world like below. We can save the memory bandwidth from this way.

```msl
float4 pos_in_c;

pos_in_c.xy = in.tex_coords * 2.0 - 1.0;
pos_in_c.y  = pos_in_c.y * -1.0;
pos_in_c.z  = depth_texture.sample(s, in.tex_coords);
pos_in_c.w  = 1.0;

float4 pos_in_w = fragmentUniforms.inverse_view_matrix *
                  fragmentUniforms.inverse_projection_matrix *
                  pos_in_c;

pos_in_w /= pos_in_w.w;
```

For the depth in the clip space, we already calculate the depth in the clip space in the geometry pass. Thus we just pass the depth textre as a input texture of geometry pass.

## 4. Fullscreen triangle.

We needs a quad for the post processing and we have passed the position and texture coordinates to the composition pass. However we do it without vertices like below. If you need more detail information please look at this [link](https://www.slideshare.net/DevCentralAMD/vertex-shader-tricks-bill-bilodeau). We can save the memory bandwidth from this way.

```msl
// Generate clip space position.
out.position.x = (float)(id / 2) * 4.0 - 1.0;
out.position.y = (float)(id % 2) * 4.0 - 1.0;
out.position.z = 0.0;
out.position.w = 1.0;

// Generate texture coordinates.
out.tex_coords.x = (float)(id / 2) * 2.0;
out.tex_coords.y = 1.0 - (float)(id % 2) * 2.0;
```
