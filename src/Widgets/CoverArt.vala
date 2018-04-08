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

  END LICENSE

  Additional contributors/authors:
  
  * Artem Anufrij <artem.anufrij@live.de>
  
***/


using Gtk;
using GLib;
using Granite;

namespace Vocal {

    public class CoverArt : Gtk.Box {

        private const int COVER_SIZE = 170;

        private Gtk.Box image_box;
        private Gtk.Image 	image;					// The actual coverart image
        private Gtk.Image 	triangle;				// The banner in the top right corner
        private Gtk.Overlay triangle_overlay;		// Overlays the banner on top of the image
        private Gtk.Overlay count_overlay;			// Overlays the count on top of the banner
        private Gtk.Label 	count_label;			// The label that stores the unplayed count
        private Gtk.Label   podcast_name_label;     // The label that show the name of the podcast
                                                        // (if it is enabled in the settings)

        public Podcast podcast;						// Refers to the podcast this coverart represents

        public CoverArt(Podcast podcast, bool? show_mimetype = false) {
            this.podcast = podcast;
            this.margin = 10;
            this.orientation = Gtk.Orientation.VERTICAL;
            this.tooltip_text = podcast.name.replace("%27", "'");
            this.valign = Align.START;

            // Load the banner to be drawn on top of the cover art
            var triangle_pixbuf = new Gdk.Pixbuf.from_resource_at_scale("/com/github/needle-and-thread/vocal/banner.png", 75, 75, true);
            triangle = new Gtk.Image.from_pixbuf(triangle_pixbuf);
            triangle.set_alignment(1, 0);

            triangle_overlay = new Gtk.Overlay();
            count_overlay = new Gtk.Overlay();

            image_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);

            set_image();
            podcast.new_cover_art_set.connect(() => {
                info("podcast image udated");
                set_image();
                info("podcast image udated 1");                
            });

            // Partially set up the overlays
            count_overlay.add(triangle);
            triangle_overlay.add(image_box);

            // Create a label to display the number of new episodes
            count_label = new Gtk.Label("");
            count_label.use_markup = true;
            count_label.get_style_context (). add_class ("coverart-overlay");
            count_label.set_alignment(1,0);
            count_label.margin_right = 5;

            count_overlay.add_overlay(count_label);
            triangle_overlay.add_overlay(count_overlay);
            
            pack_start(triangle_overlay, false, false, 0);

            string podcast_name = GLib.Uri.unescape_string(podcast.name);
			if (podcast_name == null) {
			    podcast_name = podcast.name.replace("%25", "%");
			}
			podcast_name = podcast_name.replace("&", """&amp;""");

			podcast_name_label = new Gtk.Label("<b>" + podcast_name + "</b>");
            podcast_name_label.wrap = true;
            podcast_name_label.use_markup = true;
            podcast_name_label.max_width_chars = 15;
            pack_start(podcast_name_label, false, false, 12);
            
            if(!VocalSettings.get_default_instance().show_name_label) {
                podcast_name_label.no_show_all = true;
                podcast_name_label.visible = false;
            }

            update_unplayed_count();
            podcast.unplayed_episodes_updated.connect(() => {
                update_unplayed_count();
            });

            show_all();
        }

        private void set_image() {
            if(image != null) {
                image.destroy();
            }

            try {
                var file = GLib.File.new_for_uri(podcast.coverart_uri.replace("%27", "'"));
                var icon = new GLib.FileIcon(file);

                image = new Gtk.Image.from_gicon(icon, Gtk.IconSize.DIALOG);
                image.pixel_size = COVER_SIZE;
                image.set_no_show_all(false);
                image.set_alignment(1,0);

                image_box.add(image);
            } catch (Error e) {
                warning ("Unable to load podcast cover art.");
            }

            show_all();
        }

        private void update_unplayed_count() {
            if(podcast.unplayed_count > 0) {
                set_count(podcast.unplayed_count);
                show_count();
            } else {
                hide_count();
            }
        }

        public void hide_count() {
            if (count_label != null && triangle != null) {
                count_label.set_no_show_all(true);
                count_label.hide();
                triangle.set_no_show_all(true);
                triangle.hide();
            }
        }
    
        /*
         * Sets the banner count
         */
        public void set_count(int count)
        {
            if (count_label != null) {
                count_label.use_markup = true;
                count_label.set_markup("<span foreground='white'><b>%d</b></span>".printf(count));
                count_label.get_style_context().add_class("text-shadow");
                if(count < 10) {
                    count_label.margin_right = 12;
                } else {
                    count_label.margin_right = 6;
                }
            }
        }
        
        /*
         * Shows the banner and the count
         */
        public void show_count()
        {
            if (count_label != null && triangle != null) {
                count_label.set_no_show_all(false);
                count_label.show();
                triangle.set_no_show_all(false);
                triangle.show();
            }
        }


        /*
         * Shows the name label underneath the cover art
         */
        public void show_name_label() {
            if(podcast_name_label != null) {
                podcast_name_label.no_show_all = false;
                podcast_name_label.visible = true;
            }
        }

        /*
         * Hides the name label underneath the cover art
         */
         public void hide_name_label() {
             if(podcast_name_label != null) {
                 podcast_name_label.no_show_all = true;
                podcast_name_label.visible = false;
            }
         }
    }
}
