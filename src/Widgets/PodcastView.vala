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

using Gtk;
using Gee;
using Granite;
namespace Vocal {
    
    public class PodcastView : Gtk.Box {
        
        /* Signals */
        
        public signal void on_hide_played();
        public signal void play_episode_requested();
        public signal void enqueue_episode(Episode episode);
        public signal void download_episode_requested(Episode episode);
        public signal void mark_all_episodes_as_played_requested();
        public signal void delete_local_episode_requested(Episode episode);
        public signal void delete_multiple_episodes(Gee.ArrayList<Episode> episodes);
        public signal void mark_episode_as_played_requested(Episode episode);
        public signal void mark_episode_as_unplayed_requested(Episode episode);
        public signal void download_episodes_requested(ArrayList<Episode> episodes);
        public signal void mark_multiple_episodes_as_played(Gee.ArrayList<Episode> episodes);
        public signal void mark_multiple_episodes_as_unplayed(Gee.ArrayList<Episode> episodes);
        public signal void download_all_requested();
        public signal void delete_podcast_requested();
        public signal void unplayed_count_changed(int n);
        public signal void go_back();
        
        public signal void new_cover_art_set(string path);
        
        
        public Podcast 			podcast;				// The parent podcast
        private Controller controller;
        public int 				current_episode_index;  // The index of the episode currently being used
        
        private Gtk.ListBox listbox;
        private Gtk.Paned paned;
        private Gtk.Toolbar toolbar;
        private Gtk.Box toolbar_box;
        private Gtk.Label name_label;
        private Gtk.Label count_label;
        private Gtk.Label description_label;
        private string count_string;
        
        private Gtk.Menu right_click_menu;
        
        private bool hide_played = false;
        
        private GLib.ListStore episode_model = new GLib.ListStore(typeof(Episode));
		private EpisodeDetailBox previously_selected_box;
        private EpisodeDetailBox previously_activated_box;
		private Gtk.ScrolledWindow scrolled;
		private int largest_box_size;
        
		private Gtk.Box image_box;
		private Gtk.Box details_box;
		private Gtk.Box actions_box;
		private Gtk.Box label_box;
        
		private Gtk.Image image = null;
		public Shownotes shownotes;
        
        public PodcastView (Controller controller) {
            this.controller = controller;
            
            largest_box_size = 500;
            
			this.current_episode_index = 0;
			this.orientation = Gtk.Orientation.VERTICAL;
            var horizontal_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            
			count_string = null;
            
            var toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            toolbar.get_style_context().add_class("toolbar");
            toolbar.get_style_context().add_class("library-toolbar");
            
            var go_back_button = new Gtk.Button.with_label(_("Your Podcasts"));
            go_back_button.clicked.connect(() => { go_back(); });
            go_back_button.get_style_context().add_class("back-button");
            go_back_button.margin = 6;
            
            var mark_as_played = new Gtk.Button.with_label(_("Mark All Played"));
            mark_as_played.clicked.connect(() => {
                mark_all_episodes_as_played_requested();
            });
            mark_as_played.margin = 6;
            
            toolbar.pack_start(go_back_button, false, false, 0);
            toolbar.pack_end(mark_as_played, false, false, 0);
            this.pack_start(toolbar, false, true, 0);
            
            var download_all = new Gtk.Button.from_icon_name(Utils.check_elementary() ? "browser-download-symbolic" : "document-save-symbolic", Gtk.IconSize.MENU);
            download_all.tooltip_text = _("Download all episodes");
            download_all.clicked.connect(() => {
                download_all_requested();
            });
            
            var hide_played_button = new Gtk.Button.from_icon_name("view-list-symbolic", Gtk.IconSize.MENU);
            hide_played_button.tooltip_text = _("Hide episodes that have already been played");
            hide_played_button.clicked.connect(() => {
                hide_played = !hide_played;
                
                populate_episodes();
                show_all();
            });
            
            var edit = new Gtk.Button.from_icon_name(Utils.check_elementary() ? "edit-symbolic" : "document-properties-symbolic",Gtk.IconSize.MENU);
            edit.tooltip_text = _("Edit podcast details");
            edit.button_press_event.connect((e) => {
                var edit_menu = new Gtk.Menu();
                var change_cover_art_item = new Gtk.MenuItem.with_label(_("Select different cover art"));
                change_cover_art_item.activate.connect(on_change_album_art);
                edit_menu.add(change_cover_art_item);
                edit_menu.attach_to_widget(edit, null);
                edit_menu.show_all();
                edit_menu.popup(null, null, null, e.button, e.time);
                return true;
            });
            
            var remove = new Gtk.Button.with_label(_("Unsubscribe"));
            remove.clicked.connect (() => {
                delete_podcast_requested();
            });
            remove.set_no_show_all(false);
            remove.get_style_context().add_class("destructive-action");
            remove.show();
            
            image_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            
            
            details_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            actions_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2);
            label_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            
			name_label = new Gtk.Label("Name");
			count_label = new Gtk.Label(count_string);
			name_label.max_width_chars = 15;
			name_label.wrap = true;
			name_label.justify = Gtk.Justification.CENTER;
            name_label.margin_bottom = 15;
            
            description_label = new Gtk.Label("Description");
            description_label.max_width_chars = 15;
            description_label.wrap = true;
            description_label.wrap_mode = Pango.WrapMode.WORD;
            description_label.valign = Gtk.Align.START;
            description_label.get_style_context().add_class("podcast-view-description");
            
            // Set up a scrolled window
            var description_window = new Gtk.ScrolledWindow(null, null);
            description_window.add(description_label);
            description_window.height_request = 130;
            description_window.hscrollbar_policy = Gtk.PolicyType.NEVER;
            
			name_label.get_style_context().add_class("h2");
            count_label.get_style_context().add_class("h4");
            
			label_box.pack_start(name_label, false, false, 5);
            label_box.pack_start(description_window, true, true, 0);
            
			label_box.pack_start(count_label, false, false, 0);
            
			actions_box.pack_start(download_all, true, true, 0);
            actions_box.pack_start(edit, true, true, 0);
			actions_box.pack_start(hide_played_button, true, true, 0);
			actions_box.pack_start(remove, true, true, 0);
            
			var vertical_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 5);
			vertical_box.pack_start(label_box, true, true, 0);
			vertical_box.pack_start(actions_box, false, false, 0);
            vertical_box.margin = 12;
            vertical_box.margin_bottom = 0;
            
            details_box.pack_start(vertical_box, true, true, 12);
			details_box.pack_start(image_box, false, false, 0);
            details_box.valign = Gtk.Align.FILL;
            details_box.hexpand = false;
            details_box.margin = 0;
            
			horizontal_box.pack_start(details_box, false, true, 0);
            
			var separator = new Gtk.Separator (Gtk.Orientation.VERTICAL);
			separator.margin = 0;
			horizontal_box.pack_start(separator, false, false, 0);
            
			paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
			paned.expand = true;
            horizontal_box.pack_start(paned, true, true, 0);
            
            listbox = new Gtk.ListBox();
            listbox.bind_model(episode_model, create_episode_detail_box);
            listbox.activate_on_single_click = false;
            listbox.selection_mode = Gtk.SelectionMode.MULTIPLE;
            listbox.expand = true;
            listbox.get_style_context().add_class("sidepane_listbox");
            listbox.get_style_context().add_class("view");
            
            scrolled = new Gtk.ScrolledWindow (null, null);
            scrolled.add(listbox);
            
            paned.pack1(scrolled, true, true);
            
			shownotes = new Shownotes();
            shownotes.play_button.clicked.connect(() => { play_episode_requested(); });
            shownotes.queue_button.clicked.connect(() => { enqueue_episode_internal(); });
            shownotes.on_download_episode.connect((episode) => {
                download_episode_requested(episode);
            });
            shownotes.marked_as_played.connect((episode) => {
                mark_episode_as_played_requested(episode);
            });
            shownotes.marked_as_unplayed.connect((episode) => {
                mark_episode_as_unplayed_requested(episode);
            });
            shownotes.copy_shareable_link.connect(on_copy_shareable_link);
            shownotes.send_tweet.connect(on_tweet);
            shownotes.copy_direct_link.connect(on_link_to_file);
            
            paned.pack2(shownotes, true, true);
            
            this.pack_start(horizontal_box, true, true, 0);
        }
        
        private void enqueue_episode_internal() {
            enqueue_episode(podcast.episodes[current_episode_index]);
        }
        
        private bool on_button_press_event(Gdk.EventButton e) {
            if(e.button == 3 && podcast.episodes.size > 0) {
                right_click_menu = new Gtk.Menu();
                
                GLib.List<weak ListBoxRow> rows = listbox.get_selected_rows();
                var selected_episodes = new Gee.ArrayList<Episode>();
                
                if(rows.length() > 1) {
                    var mark_played_menuitem = new Gtk.MenuItem.with_label(_("Mark selected episodes as played"));
                    
                    mark_played_menuitem.activate.connect(() => {
                        foreach(ListBoxRow row in rows) {
                            var episode = episode_model.get_item(row.get_index()) as Episode;
                            selected_episodes.add(episode);
                        }
                        
                        mark_multiple_episodes_as_played(selected_episodes);
                        reset_unplayed_count();
                    });
                    right_click_menu.add(mark_played_menuitem);
                    
                    var mark_unplayed_menuitem = new Gtk.MenuItem.with_label(_("Mark selected episodes as new"));
                    mark_unplayed_menuitem.activate.connect(() => {
                        foreach(ListBoxRow row in rows) {
                            var episode = episode_model.get_item(row.get_index()) as Episode;
                            selected_episodes.add(episode);
                        }
                        
                        mark_multiple_episodes_as_unplayed(selected_episodes);
                        reset_unplayed_count();
                    });
                    right_click_menu.add(mark_unplayed_menuitem);
                    
                    var delete_menuitem = new Gtk.MenuItem.with_label(_("Delete local files for selected episodes"));
                    delete_menuitem.activate.connect(() => {
                        
                        Gtk.MessageDialog msg = new Gtk.MessageDialog (controller.window, Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING, Gtk.ButtonsType.NONE,
                        _("Are you sure you want to delete the downloaded files for the selected episodes?"));
                        
                        msg.add_button ("_No", Gtk.ResponseType.CANCEL);
                        Gtk.Button delete_button = (Gtk.Button) msg.add_button("_Yes", Gtk.ResponseType.YES);
                        delete_button.get_style_context().add_class("destructive-action");
                        
                        var image = new Gtk.Image.from_icon_name("dialog-question", Gtk.IconSize.DIALOG);
                        msg.image = image;
                        msg.image.show_all();
                        
                        msg.response.connect ((response_id) => {
                            switch (response_id) {
                                case Gtk.ResponseType.YES:
                                foreach(ListBoxRow row in rows) {
                                    var episode = episode_model.get_item(row.get_index()) as Episode;
                                    selected_episodes.add(episode);
                                }
                                
                                delete_multiple_episodes(selected_episodes);
                                break;
                                case Gtk.ResponseType.NO:
                                break;
                            }
                            msg.destroy();
                        });
                        
                        msg.show ();
                    });
                    right_click_menu.add(delete_menuitem);
                } else {
                    var episode = episode_model.get_item(listbox.get_selected_row().get_index()) as Episode;
                    
                    if(episode.status == EpisodeStatus.UNPLAYED) {
                        var mark_played_menuitem = new Gtk.MenuItem.with_label(_("Mark as played"));
                        mark_played_menuitem.activate.connect(() => {
                            mark_episode_as_played_requested(episode);
                        });
                        right_click_menu.add(mark_played_menuitem);
                    } else {
                        var mark_unplayed_menuitem = new Gtk.MenuItem.with_label(_("Mark as unplayed"));
                        mark_unplayed_menuitem.activate.connect(() => {
                            mark_episode_as_played_requested(episode);
                        });
                        right_click_menu.add(mark_unplayed_menuitem);
                    }
                    
                    if(episode.current_download_status == DownloadStatus.DOWNLOADED) {
                        var delete_menuitem = new Gtk.MenuItem.with_label(_("Delete Local File"));
                        
                        delete_menuitem.activate.connect(() => {
                            Gtk.MessageDialog msg = new Gtk.MessageDialog (controller.window, Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING, Gtk.ButtonsType.NONE,
                            _("Are you sure you want to delete the downloaded episode '%s'?").printf(podcast.episodes[current_episode_index].title.replace("%27", "'")));
                            
                            msg.add_button ("_No", Gtk.ResponseType.CANCEL);
                            Gtk.Button delete_button = (Gtk.Button) msg.add_button("_Yes", Gtk.ResponseType.YES);
                            delete_button.get_style_context().add_class("destructive-action");
                            
                            var image = new Gtk.Image.from_icon_name("dialog-question", Gtk.IconSize.DIALOG);
                            msg.image = image;
                            msg.image.show_all();
                            
                            msg.response.connect ((response_id) => {
                                switch (response_id) {
                                    case Gtk.ResponseType.YES:
                                    delete_local_episode_requested(episode);
                                    break;
                                    case Gtk.ResponseType.NO:
                                    break;
                                }
                                
                                msg.destroy();
                            });
                            msg.show ();
                        });
                        
                        right_click_menu.add(delete_menuitem);
                    }
                }
                
                right_click_menu.show_all();
                right_click_menu.popup(null, null, null, e.button, e.time);
            }
            
            return false;
        }
        
        public void set_podcast(Podcast podcast) {
            this.podcast = podcast;
            
            if(image != null) {
                image_box.remove(image);
                image = null;
            }
            
            try {
                var cover = GLib.File.new_for_uri(podcast.coverart_uri);
                var icon = new GLib.FileIcon(cover);
				image = new Gtk.Image.from_gicon(icon, Gtk.IconSize.DIALOG);
                image.pixel_size = 250;
                image.margin = 0;
                image.get_style_context().add_class("podcast-view-coverart");
                
                image_box.pack_start(image, true, true, 0);
            } catch (Error e) {
                error(e.message);
            }
            
			name_label.set_text(podcast.name.replace("%27", "'"));
            description_label.set_text(GLib.Uri.unescape_string(podcast.description).replace("""\n""",""));
            
            populate_episodes();
            
            // Select the first podcast
            var first_row = listbox.get_row_at_index(0);
            //  listbox.select_row(first_row);
            
            show_all();
        }
        
        /*
        * When a row is activated, clear the unplayed icon if there is one and request
        * the corresponding episode be played
        */
        private void on_row_activated(ListBoxRow? row) {
            
            if(previously_activated_box != null) {
                previously_activated_box.clear_now_playing();
            }
            
            if(podcast.episodes[current_episode_index].status == EpisodeStatus.UNPLAYED) {
                
                // Mark the box as played
                /*          previously_activated_box.mark_as_played();
                
                Set the new unplayed count in the top area
                unplayed_count--;
                set_unplayed_text();
                
                Re-mark the box so it doesn't show if hide played is enabled
                if(controller.settings.hide_played && unplayed_count > 0) {
                    previously_activated_box. get_parent (). set_no_show_all(true);
                    previously_activated_box. get_parent (). visible = false;
                }  */
                
                // No matter what, mark this box as now playing
                previously_activated_box.mark_as_now_playing();
                
                play_episode_requested();
            }
        }
        
        public Widget create_episode_detail_box(Object item) {
            Episode episode = item as Episode;
            
            var episode_detail_box = new EpisodeDetailBox(episode, controller.on_elementary);
            //  episode_detail_box.streaming_button_clicked.connect(on_streaming_button_clicked);
            episode_detail_box.get_style_context().add_class("episode-list");
            episode_detail_box.margin_top = 6;
            episode_detail_box.margin_left = 6;
            episode_detail_box.border_width = 0;
            if(episode_detail_box.top_box_width > this.largest_box_size) {
                this.largest_box_size = episode_detail_box.top_box_width;
            }
            episode_detail_box.download_button.clicked.connect(() => {
                episode_detail_box.hide_download_button();
                download_episode_requested(episode);
            });
            
            /*
            if(episode == controller.current_episode) {
                episode_detail_box.mark_as_now_playing();
            }
            */
            
            episode.played_status_updated.connect(() => {
                episode_detail_box.update_played_status();
            });
            
            return episode_detail_box;
        }
        
        public void populate_episodes(int? limit = 25) {
            episode_model.remove_all();
            
            if(this.podcast.episodes.size > 0) {
                listbox.row_selected.connect((row) => {
                    var episode = episode_model.get_item(row.get_index()) as Episode;
                    shownotes.set_episode(episode);
                });
                listbox.row_activated.connect(on_row_activated);
                
                for (int i = 0; i < podcast.episodes.size; i++) {
                    if(hide_played) {
                        if(podcast.episodes[i].status == EpisodeStatus.UNPLAYED) {
                            episode_model.append(podcast.episodes[i]);
                        }
                    } else {
                        episode_model.append(podcast.episodes[i]);
                    }
                }
                
                var increase_button = new Gtk.Button.with_label(_("Show more episodes"));
                increase_button.clicked.connect(() => {
                    //  populate_episodes(this.limit += 25);
                    this.show_all();
                });
                
                /*
                if(controller.settings.hide_played && unplayed_count == 0) {
                    var no_new_label = new Gtk.Label(_("No new episodes."));
                    no_new_label.margin_top = 25;
                    no_new_label.get_style_context().add_class("h3");
                    listbox.prepend(no_new_label);
                }
                */
            } else {
                var empty_label = new Gtk.Label(_("No episodes available."));
                empty_label.justify = Gtk.Justification.CENTER;
                empty_label.margin = 10;
                
                empty_label.get_style_context().add_class("h3");
                listbox.prepend(empty_label);
            }
            
            listbox.button_press_event.connect(on_button_press_event);
            
            set_unplayed_text();
        }
        
        /*
        * Resets the unplayed count and iterates through the boxes to obtain a new one
        */
        public void reset_unplayed_count() {
            
            /*      int previous_count = unplayed_count;
            
            unplayed_count = 0;
            
            foreach(Episode e in podcast.episodes) {
                if(e.status == EpisodeStatus.UNPLAYED)
                unplayed_count++;
            }
            
            set_unplayed_text();
            
            // Is the number of unplayed episodes now different?
            if(previous_count != unplayed_count)
            unplayed_count_changed(unplayed_count);  */
        }
        
        private void on_change_album_art() {
            var file_chooser = new Gtk.FileChooserDialog (_("Select Album Art"),
            controller.window,
            Gtk.FileChooserAction.OPEN,
            _("Cancel"), Gtk.ResponseType.CANCEL,
            _("Open"), Gtk.ResponseType.ACCEPT);
            
            var all_files_filter = new Gtk.FileFilter();
            all_files_filter.set_filter_name(_("All files"));
            all_files_filter.add_pattern("*");
            
            var opml_filter = new Gtk.FileFilter();
            opml_filter.set_filter_name(_("Image Files"));
            opml_filter.add_mime_type("image/png");
            opml_filter.add_mime_type("image/jpeg");
            
            file_chooser.add_filter(opml_filter);
            file_chooser.add_filter(all_files_filter);
            
            file_chooser.modal = true;
            
            int decision = file_chooser.run();
            string file_name = file_chooser.get_filename();
            
            file_chooser.destroy();
            
            //If the user selects a file, get the name and parse it
            if (decision == Gtk.ResponseType.ACCEPT) {
                GLib.File cover = GLib.File.new_for_path(file_name);
                var icon = new GLib.FileIcon(cover);
                image.gicon = icon;
                image.pixel_size = 250;
                
                new_cover_art_set(file_name);
            }
        }
        
        /*
        * Sets the unplayed text (assumes the unplayed count has already been set)
        */
        public void set_unplayed_text() {
            string count_string = null;
            /*    if(unplayed_count > 0) {
                count_string = _("%d unplayed episodes".printf(unplayed_count));
            } else {
                count_string = "";
            }  */
            count_label.set_text(count_string);
        }
        
        public void select_episode(Episode episode_to_select) {
            //  populate_episodes(podcast.episodes.size);
            
            for(int i = 0; i < episode_model.get_n_items(); i++) {
                Episode episode = episode_model.get_item(i) as Episode;
                
                if(episode_to_select.title == episode.title) {
                    listbox.select_row(listbox.get_row_at_index(i));
                    break;
                }
            }
        }
        
        private void on_link_to_file() {
            Gdk.Display display = controller.window.get_display ();
            Gtk.Clipboard clipboard = Gtk.Clipboard.get_for_display (display, Gdk.SELECTION_CLIPBOARD);
            string uri = podcast.episodes[current_episode_index].uri;
            clipboard.set_text(uri,uri.length);
        }
        
        private void on_tweet() {
            string uri = Utils.get_shareable_link_for_episode(podcast.episodes[current_episode_index]);
            string message_text = GLib.Uri.escape_string(_("I'm listening to %s from %s").printf(podcast.episodes[current_episode_index].title,podcast.episodes[current_episode_index].parent.name));
            string new_tweet_uri = "https://twitter.com/intent/tweet?text=%s&url=%s".printf(message_text, GLib.Uri.escape_string(uri));
            Gtk.show_uri (null, new_tweet_uri, 0);
        }
        
        private void on_copy_shareable_link() {
            Gdk.Display display = controller.window.get_display ();
            Gtk.Clipboard clipboard = Gtk.Clipboard.get_for_display (display, Gdk.SELECTION_CLIPBOARD);
            string uri = Utils.get_shareable_link_for_episode(podcast.episodes[current_episode_index]);
            clipboard.set_text(uri,uri.length);
        }
    }
}
