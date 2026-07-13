// mayhem/oracle.c — behavioral known-answer oracle for gdk-pixbuf (authored for the anti-reward-hack
// sabotage check; the primary functional suite is upstream's `meson test`, run by mayhem/test.sh).
// Decodes an image through the public gdk_pixbuf_new_from_file() API and prints its geometry on
// stdout. A library neutered to exit(0) never reaches the printf, so test.sh's known-answer grep
// fails — proving the oracle asserts behavior, not exit status.
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <image>\n", argv[0]);
        return 2;
    }
    GError *e = NULL;
    GdkPixbuf *p = gdk_pixbuf_new_from_file(argv[1], &e);
    if (!p) {
        fprintf(stderr, "loadfail %s\n", e ? e->message : "?");
        return 2;
    }
    printf("DIMS %dx%d ch=%d bps=%d alpha=%d\n",
           gdk_pixbuf_get_width(p),
           gdk_pixbuf_get_height(p),
           gdk_pixbuf_get_n_channels(p),
           gdk_pixbuf_get_bits_per_sample(p),
           gdk_pixbuf_get_has_alpha(p));
    g_object_unref(p);
    return 0;
}
