// Copyright 2020 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <stdint.h>
#include <gdk-pixbuf/gdk-pixbuf.h>

#define WIDTH 10
#define HEIGHT 20
#define ROWSTRIDE (WIDTH * 4)

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (!(size >= WIDTH * HEIGHT * 4)) {
        return 0;
    }
    GdkPixbuf *pixbuf, *tmp;
    GBytes *bytes;
    bytes = g_bytes_new_static(data, size);
    pixbuf = g_object_new(GDK_TYPE_PIXBUF,
            "width", WIDTH,
            "height", HEIGHT,
            "rowstride", ROWSTRIDE,
            "bits-per-sample", 8,"n-channels", 3,
            "has-alpha", FALSE,
            "pixel-bytes", bytes,
            NULL);
    g_bytes_unref(bytes);
    if (pixbuf == NULL) {
        return 0;
    }
    gdk_pixbuf_scale(pixbuf, pixbuf,
            0, 0, 
            gdk_pixbuf_get_width(pixbuf) / 4, 
            gdk_pixbuf_get_height(pixbuf) / 4,
            0, 0, 0.5, 0.5,
            GDK_INTERP_NEAREST);
    unsigned int rot_amount = ((unsigned int) data[0]) % 4;
    tmp = gdk_pixbuf_rotate_simple(pixbuf, rot_amount * 90);
    g_clear_object(&tmp);
    tmp = gdk_pixbuf_flip(pixbuf, TRUE);
    g_clear_object(&tmp);
    tmp = gdk_pixbuf_composite_color_simple(pixbuf,
            gdk_pixbuf_get_width(pixbuf) / 4, 
            gdk_pixbuf_get_height(pixbuf) / 4,
            GDK_INTERP_NEAREST,
            128,
            8,
            G_MAXUINT32,
            G_MAXUINT32/2);
    g_clear_object(&tmp);

    char *buf = (char *) calloc(size + 1, sizeof(char));
    memcpy(buf, data, size);
    buf[size] = '\0';

    gdk_pixbuf_set_option(pixbuf, buf, buf);
    gdk_pixbuf_get_option(pixbuf, buf);
    tmp = gdk_pixbuf_new_from_data(gdk_pixbuf_get_pixels(pixbuf),
            GDK_COLORSPACE_RGB,
            FALSE,
            gdk_pixbuf_get_bits_per_sample(pixbuf),
            gdk_pixbuf_get_width(pixbuf), 
            gdk_pixbuf_get_height(pixbuf),
            gdk_pixbuf_get_rowstride(pixbuf),
            NULL,
            NULL);
    if (tmp != NULL) {
        GdkPixbuf *flipped = gdk_pixbuf_flip(tmp, TRUE);
        g_clear_object(&flipped);
        g_clear_object(&tmp);
    }

    free(buf);
    g_object_unref(pixbuf);
    return 0;
}
