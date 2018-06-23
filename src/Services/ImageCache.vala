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

        private const int COVER_SIZE = 170;

        private static ImageCache cache;
        private Gee.HashMap<string, Gdk.Pixbuf> map;

        private ImageCache() {
            map = new Gee.HashMap<string, Gdk.Pixbuf> ();
        }

        public static ImageCache instance() {
            if(cache == null) {
                cache = new ImageCache();
            }

            return cache;
        }

        public async void set_image(Gtk.Image image, string path, int size) throws Error {
            GLib.File file = Utils.open_file(path);

            if(map.contains(path)) {
                info("cache");
                Gdk.Pixbuf pixbuf = map.get(path);
                create_cover_image(image, pixbuf, size);
            } else {
                info("no cache");

                GLib.InputStream stream = yield file.read_async ();
                Gdk.Pixbuf pixbuf = yield new Gdk.Pixbuf.from_stream_async (stream);
                
                create_cover_image(image, pixbuf, size);
                map.set(path, pixbuf);
                stream.close();
            }
        }

        public static void create_cover_image (Gtk.Image image, Gdk.Pixbuf pixbuf, int image_size) throws Error {
            Gdk.Pixbuf cover_image = pixbuf;
    
            if (cover_image.height == cover_image.width)
                cover_image = cover_image.scale_simple (image_size, image_size, Gdk.InterpType.BILINEAR);
    
            if (cover_image.height > cover_image.width) {
    
                int new_height = image_size * cover_image.height / cover_image.width;
                int new_width = image_size;
                int offset = (new_height - new_width) / 2;
    
                cover_image = new Gdk.Pixbuf.subpixbuf(cover_image.scale_simple (new_width, new_height, Gdk.InterpType.BILINEAR), 0, offset, image_size, image_size);
    
            } else if (cover_image.height < cover_image.width) {
    
                int new_height = image_size;
                int new_width = image_size * cover_image.width / cover_image.height;
                int offset = (new_width - new_height) / 2;
    
                cover_image = new Gdk.Pixbuf.subpixbuf(cover_image.scale_simple (new_width, new_height, Gdk.InterpType.BILINEAR), offset, 0, image_size, image_size);
            }
    
            if(image != null) {
                image.clear();
    
                image.set_from_pixbuf (cover_image);
            }
        }
    }
}
