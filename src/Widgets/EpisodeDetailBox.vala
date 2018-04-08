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
***/


namespace Vocal {
    public class EpisodeDetailBox : Gtk.Box {
        
        public signal void streaming_button_clicked(Episode episode);
        public signal void download_button_clicked(Episode episode);
        
        private bool now_playing;
        
        private Episode episode;
        private int 	   top_box_width;
        
        private Gtk.Box unplayed_box;
        private Gtk.Label   title_label;
        private Gtk.Label   release_label;
        private Gtk.Image   unplayed_image;
        private Gtk.Image   now_playing_image;
        private  Gtk.Button  download_button;
        private  Gtk.Button  streaming_button;
        private Gtk.Label   description_label;
        private bool new_episodes_view;
        
		/*
        * Creates a new episode detail box given an episode, and index, a box_index (corresponding
        * index number for this box in the list in the side pane), and whether Vocal is running
        * in elementary (determines the icons).
        */
        public EpisodeDetailBox(Episode episode, bool on_elementary,  bool? new_episodes_view = false) {
            this.episode = episode;
            this.new_episodes_view = new_episodes_view;

            orientation = Gtk.Orientation.VERTICAL;
            set_size_request(100, 25);
            var top_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            pack_start(top_box, false, false, 0);
            
            this.homogeneous = false;
            this.border_width = 5;
            
            now_playing = false;
            
            string location_image = null;
            string streaming_image = "media-playback-start-symbolic";
            
            var download_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            download_box.set_size_request(25, 25);
            
            var streaming_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            streaming_box.set_size_request(25, 25);
            
            // Create the now playing image, but don't actually use it anywhere yet
            now_playing_image = new Gtk.Image.from_icon_name("media-playback-start-symbolic", Gtk.IconSize.BUTTON);
            now_playing_image.has_tooltip = true;
            now_playing_image.tooltip_text = _("This episode is currently being played");
            
            // Determine whether or not the episode has been downloaded
            if(episode.download_status != DownloadStatus.DOWNLOADED) {
                if(on_elementary) {
                    location_image = "browser-download-symbolic";
                } else {
                    location_image = "document-save-symbolic";
                }
                streaming_image =  "network-wireless-signal-excellent-symbolic";
            }
            
            unplayed_image = new Gtk.Image.from_icon_name("starred-symbolic", Gtk.IconSize.BUTTON);
            unplayed_image.valign = Gtk.Align.START;
            
            unplayed_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            unplayed_box.set_size_request(25, 25);
            unplayed_box.pack_start(unplayed_image, false, false, 0);
            
            top_box.pack_start(unplayed_box, false, false, 0);
            
            update_played_status();
            episode.played_status_updated.connect(() => {
                update_played_status();
            });
            
            if (new_episodes_view) {
			    var file = GLib.File.new_for_uri(episode.parent.coverart_uri);
			    var icon = new GLib.FileIcon(file);
			    var image = new Gtk.Image.from_gicon(icon, Gtk.IconSize.DIALOG);
			    image.margin = 12;
			    image.margin_top = 0;
			    image.margin_bottom = 0;
			    image.pixel_size = 75;
			    unplayed_box.pack_start (image, false, false, 0);
            }

            // Set up the streaming button
            streaming_button = new Gtk.Button.from_icon_name(streaming_image, Gtk.IconSize.BUTTON);
            streaming_button.expand = false;
            streaming_button.relief = Gtk.ReliefStyle.NONE;
            streaming_button.has_tooltip = true;
            
            streaming_button.clicked.connect(() => {
                streaming_button_clicked(episode);
            });
            
            streaming_box.pack_start(streaming_button, false, false, 0);

            // If the episode has not been downloaded, show a download button
            download_button = new Gtk.Button.from_icon_name(location_image, Gtk.IconSize.BUTTON);
            download_button.expand = false;
            download_button.relief = Gtk.ReliefStyle.NONE;
            download_button.has_tooltip = true;
            download_button.tooltip_text = _("Download Episode");
            download_button.clicked.connect(() => {
                download_button_clicked(this.episode);
            });
            download_box.pack_start(download_button, false, false, 0);

            update_download_button_status();
            episode.download_status_changed.connect(() => {
                update_download_button_status();
            });

            title_label = new Gtk.Label("<b>%s</b>".printf(GLib.Markup.escape_text(episode.title.replace("%27", "'").replace("&amp;", "&"))));
            title_label.set_use_markup(true);
            title_label.halign = Gtk.Align.START;
            title_label.set_property("xalign", 0);
            title_label.justify = Gtk.Justification.LEFT;
            title_label.wrap = true;
            
            var label_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 5);
            label_box.margin = 0;
            label_box.pack_start(title_label, true, true, 0);
            label_box.expand = false;
            
            if(episode.datetime_released != null && episode.date_released != "(null)") {
            
            if (new_episodes_view) {
                var name_label = new Gtk.Label (episode.parent.name);
                name_label.halign = Gtk.Align.START;
                name_label.justify = Gtk.Justification.LEFT;
                name_label.wrap = true;
                label_box.pack_start (name_label, true, true, 0);
            }
            
            if(episode.datetime_released != null) {
                release_label = new Gtk.Label(episode.datetime_released.format("%x"));
            } else {
                release_label = new Gtk.Label(episode.date_released);
            }
            release_label.halign = Gtk.Align.START;
            release_label.justify = Gtk.Justification.LEFT;
            
            label_box.pack_start(release_label, true, true, 0);
            top_box.pack_start(label_box, true, true, 0);
            
            top_box_width = top_box.width_request;
            
            string text = Utils.html_to_markup(episode.description);
            
            // Remove repeated whitespace from description before adding to label.
            Regex condense_spaces = new Regex("\\s{2,}");
            text = condense_spaces.replace(text, -1, 0, " ").strip();
            
            description_label = new Gtk.Label(text != "(null)" ? text : _("No description available."));
            description_label.justify = Gtk.Justification.LEFT;
            description_label.set_use_markup(true);
            description_label.set_ellipsize(Pango.EllipsizeMode.END);
            description_label.lines = 2;
            description_label.max_width_chars = 10;
            description_label.single_line_mode = true;
            description_label.margin = 12;
            if (new_episodes_view == false) {
                description_label.margin_left = 25;
            }

            description_label.set("xalign", 0);
            
            pack_end(description_label);
            
            this.get_style_context().add_class("episode_detail_box");
            }
        }
        
        /*
        * Removes the now playing image from the box
        */
        public void clear_now_playing() {
            if(now_playing) {
                unplayed_box.remove(now_playing_image);
                now_playing = false;
            }
        }
        
        private void update_download_button_status() {
            if(episode.download_status == DownloadStatus.DOWNLOADED) {
                hide_download_button();
            } else {
                show_download_button();
            }
        }
        
        public void hide_download_button() {
            streaming_button.tooltip_text = _("Stream Episode");
            download_button.set_no_show_all(true);
            download_button.hide();
            show_all();
        }
        
        public void show_download_button() {
            download_button.set_no_show_all(false);
            download_button.show();
        }
        
        public void hide_playback_button() {
            streaming_button.tooltip_text = _("Play");
            streaming_button.set_no_show_all(true);
            streaming_button.hide();
        }
        
        public void mark_as_now_playing() {
            // It's possible that now_playing_image pointed to the unplayed icon before,
            // so set it to match the icon for now playing
            
            now_playing_image.icon_name = "media-playback-start-symbolic";
            
            unplayed_box.pack_start(now_playing_image, false, false, 0);
            now_playing = true;
        }
        
        public void update_played_status() {
            if(episode.status == EpisodeStatus.UNPLAYED && new_episodes_view == false) {
                mark_as_unplayed();
            } else {
                mark_as_played();
            }
            
            show_all();
        }
        
        private void mark_as_played() {
            unplayed_image.no_show_all = true;
            unplayed_image.hide();
        }
        
        private void mark_as_unplayed() {
            unplayed_image.no_show_all = false;
            unplayed_image.show();
        }
        
        public void show_playback_button() {
            string streaming_image;
            if(episode.download_status == DownloadStatus.DOWNLOADED) {
                streaming_image =  "media-playback-start-symbolic";
            } else {
                streaming_image =  "network-wireless-signal-excellent-symbolic";
            }
            
            Gtk.Image image = new Gtk.Image.from_icon_name(streaming_image, Gtk.IconSize.BUTTON);
            streaming_button.set_image(image);
            
            if(episode.download_status == DownloadStatus.DOWNLOADED) {
                streaming_button.tooltip_text = _("Play");
                
            } else {
                streaming_button.tooltip_text = _("Stream Episode");
            }
            
            streaming_button.set_no_show_all(false);
            streaming_button.show();
        }
    }
}
