fbink and fbink-static: FBInk v1.25.0 (https://github.com/NiLuJe/FBInk), license GPL-3.0 (see FBInk-LICENSE.txt).
Built from the unmodified source FBInk-v1.25.0.tar.xz (sha256 d598e99ed20994e08e1bb768512bc55c97cee941ffe6b1ac237aa754690e1ed5)
with: make staticlib staticbin MINIMAL=true BITMAP=true IMAGE=true KOBO=true  (ARMv7, hard-float)
  fbink         -> dynamic, glibc <= 2.7 (the Kobo ships 2.15)
  fbink-static  -> static (musl), in case the previous one does not start
Features: text with a bitmap font + images (JPEG, PNG, TGA, BMP, GIF, PNM). No OpenType.
