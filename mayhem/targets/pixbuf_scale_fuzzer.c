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

#include "fuzzer_temp_file.h"

// Derive a bounded scale dimension from input bytes so libFuzzer can explore the scaler
// (the historical harness scaled every input to a fixed height==size, exercising one narrow
// path and discovering 0 new edges). Bound to a sane range to avoid multi-GB allocations that
// would just OOM without covering new code.
static int scaled_dim(const uint8_t *data, size_t size, size_t i) {
    int v = (i < size) ? (int) data[i] : 1;
    return 1 + (v % 512);   // 1..512
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 1) {
        return 0;
    }
    GError *error = NULL;
    GdkPixbuf *pixbuf;

    char *tmpfile = fuzzer_get_tmpfile(data, size);

    int w = scaled_dim(data, size, 0);
    int h = scaled_dim(data, size, 1);

    // preserve-aspect variants over the same decode+scale code path
    pixbuf = gdk_pixbuf_new_from_file_at_scale(tmpfile, w, h, TRUE, &error);
    if (pixbuf != NULL) { g_clear_object(&pixbuf); } else { g_clear_error(&error); }

    pixbuf = gdk_pixbuf_new_from_file_at_scale(tmpfile, w, h, FALSE, &error);
    if (pixbuf != NULL) { g_clear_object(&pixbuf); } else { g_clear_error(&error); }

    // fixed-size variant
    pixbuf = gdk_pixbuf_new_from_file_at_size(tmpfile, w, h, &error);
    if (pixbuf != NULL) { g_clear_object(&pixbuf); } else { g_clear_error(&error); }

    // decode once then drive the in-memory scaler with several interpolation modes
    pixbuf = gdk_pixbuf_new_from_file(tmpfile, &error);
    if (pixbuf != NULL) {
        GdkInterpType interp = (GdkInterpType) ((size > 2 ? data[2] : 0) % 4);
        GdkPixbuf *scaled = gdk_pixbuf_scale_simple(pixbuf, w, h, interp);
        g_clear_object(&scaled);
        g_clear_object(&pixbuf);
    } else {
        g_clear_error(&error);
    }

    fuzzer_release_tmpfile(tmpfile);
    return 0;
}
