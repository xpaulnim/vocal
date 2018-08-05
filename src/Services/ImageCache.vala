/***
  BEGIN LICENSE

  Copyright (C) 2014-2015 Nathan Dyer <mail@nathandyer.me>
  This program is free software: you can redistribute it and/or modify it
  under the terms of the GNU Lesser General Public License version 3, as
  published by the Free Software Foundation.

  This program is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranties of
  MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
  PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along
  with this program.  If not, see <http://www.gnu.org/licenses>
n
  END LICENSE

  Additional contributors/authors:

  * Akshay Shekher <voldyman666@gmail.com>

***/

namespace Vocal {

    public class ImageCache : GLib.Object {

        private static  GLib.Once<ImageCache> _instance;

        private Gee.HashSet<string> queue = new Gee.HashSet<string>();
        private Gee.HashMap<string, Gdk.Pixbuf> cache = new Gee.HashMap<string, Gdk.Pixbuf>();

        private const int NAP_TIME = 10000; // 0.5 Seconds
        private const int MAX_TIMEOUT = 30000; // 30 Seconds

        private ImageCache() {}

        public static unowned ImageCache instance () {
            return _instance.once (() => { return new ImageCache (); });
        }

        public async void set_image(Gtk.Image image, string path, int image_size, bool cache_pixbuf = false) throws Error {
            GLib.File file = Utils.open_file(path);
            
            if (cache.has_key(path)) {
                Gdk.Pixbuf cover_image = cache.get(path);
                create_cover_image(image, cover_image, image_size);
            } else if(!queue.contains(path)) {
                queue.add(path);

                GLib.InputStream stream = yield file.read_async ();
                Gdk.Pixbuf cover_image = yield new Gdk.Pixbuf.from_stream_async (stream);

                create_cover_image(image, cover_image, image_size);
                
                queue.remove(path);
                if(cache_pixbuf) {
                    cache.@set(path, cover_image);
                }
            } else {
                wait_for_image_to_load.begin (path, image, image_size);
            }
        }

        private static void create_cover_image (Gtk.Image image, Gdk.Pixbuf pixbuf, int image_size) throws Error {
            Gdk.Pixbuf cover_image = pixbuf;

            if (cover_image.height == cover_image.width)
                cover_image = cover_image.scale_simple (image_size, image_size, Gdk.InterpType.BILINEAR);
            if (cover_image.height > cover_image.width) {
                int new_height = image_size * cover_image.height / cover_image.width;
                int new_width = image_size;
                int offset = (new_height - new_width) / 2;

                cover_image = new Gdk.Pixbuf.subpixbuf(
                    cover_image.scale_simple (new_width, new_height, Gdk.InterpType.BILINEAR), 0, offset, image_size, image_size);
            } else if (cover_image.height < cover_image.width) {
                int new_height = image_size;
                int new_width = image_size * cover_image.width / cover_image.height;
                int offset = (new_width - new_height) / 2;

                cover_image = new Gdk.Pixbuf.subpixbuf(
                    cover_image.scale_simple (new_width, new_height, Gdk.InterpType.BILINEAR), offset, 0, image_size, image_size);
            }

            if(image != null) {
                image.clear();

                image.set_from_pixbuf (cover_image);
            }
        }
        
        private async void wait_for_image_to_load (string path, Gtk.Image image, int image_size) {
            int total_wait = 0;
            GLib.Timeout.add(NAP_TIME, () => {
                total_wait+=NAP_TIME;
                if (cache.has_key(path) || (total_wait > MAX_TIMEOUT)) {
                    create_cover_image(image, cache.get(path), image_size);
                    return false;
                }
                return true;
            });
        }
    }
}
