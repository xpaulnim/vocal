/***
  BEGIN LICENSE

  Copyright (C) 2014-2018 Nathan Dyer <mail@nathandyer.me>
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

using Clutter;
using Granite;
using Granite.Services;
using Granite.Widgets;

namespace Vocal {

    public class MainWindow : Gtk.Window {

        /* Core components */

        private Controller controller;

        /* Primary widgets */

        public Toolbar toolbar;
        private Gtk.Box box;
        public Welcome welcome;
        private DirectoryView directory;
        public SearchResultsView search_results_view;
        private Gtk.Stack notebook;
        public PodcastView podcast_view;
        private Gtk.Box import_message_box;

        /* Secondary widgets */

        private AddFeedDialog add_feed;
        private DownloadsPopover downloads;
        public ShowNotesPopover shownotes;
        private QueuePopover queue_popover;
        private Gtk.MessageDialog missing_dialog;
        private SettingsDialog settings_dialog;
        public VideoControls video_controls;
        private Gtk.Revealer return_revealer;
        private Gtk.Button return_to_library;
        private Gtk.Box search_results_box;

        /* Icon views and related variables */

        public AllPodcastsView all_podcasts_view;
        public Gtk.ScrolledWindow directory_scrolled;
        public Gtk.ScrolledWindow search_results_scrolled;

        /* Video playback */

        public Clutter.Actor actor;
        public GtkClutter.Actor bottom_actor;
        public GtkClutter.Actor return_actor;
        public Clutter.Stage stage;
        public GtkClutter.Embed video_widget;
        
        /* Miscellaneous Global Variables */
        public CoverArt current_episode_art;
        public Gtk.Widget current_widget;
        public Gtk.Widget previous_widget;

        private bool ignore_window_state_change = false;
        private uint hiding_timer = 0; // Used for hiding video controls
        private bool mouse_primary_down = false;
        public bool fullscreened = false;
        private Gtk.Box parent_box = null;

        public MainWindow (Controller controller) {
        
            this.controller = controller;

            const string ELEMENTARY_STYLESHEET = """

                @define-color colorPrimary #af81d6;

                .album-artwork {
                    border-color: shade (mix (rgb (255, 255, 255), #fff, 0.5), 0.9);
                    border-style: solid;
                    border-width: 3px;

                    background-color: #8e8e93;
                }

                .controls {
                    background-color: #FFF;
                }


                .episode-list {
                    border-bottom: 0.5px solid #8a9580;
                }

                .coverart, .directory-art {
                    background-color: #FFF;

                    border-color: shade (mix (rgb (255, 255, 255), #fff, 0.5), 0.9);
                    box-shadow: 3px 3px 3px #777;
                    border-style: solid;
                    border-width: 0.4px;

                    color: #000;
                }

                .coverart-overlay {
                    font-size: 1.7em;
                    font-family: sans;
                }

                .directory-art-image {
                    border-bottom: 1px solid #EFEFEF;
                }

                .directory-flowbox {
                    background-color: #E8E8E8;
                }

                .download-detail-box {
                    border-bottom: 0.5px solid #8a9580;
                }

                .h2 {
                    font-size: 1.5em;
                }

                .h3 {
                    font-size: 1.3em;
                }

                .library-toolbar {
                    background-image: -gtk-gradient (linear,
                                         left top, left bottom,
                                         from (shade (@bg_color, 0.9)),
                                         to (@bg_color));
                    border-bottom: 0.3px solid black;
                }

                .notebook-art {
                    /*background-color: #D8D8D8;*/
                }

                .podcast-view-coverart {
                    box-shadow: 5px 5px 5px #777;
                    border-style: none;
                }

                .podcast-view-toolbar {
                }


                .rate-button {
                    color: shade (#000, 1.60);
                }


                .sidepane-toolbar {
                    background-color: #fff;
                }

                """;

            info ("Loading CSS provider.");
            var css_provider = new Gtk.CssProvider ();
            css_provider.load_from_buffer (ELEMENTARY_STYLESHEET.data);
            var screen = Gdk.Screen.get_default ();
            var style_context = this.get_style_context ();
            style_context.add_provider_for_screen(screen, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

            this.set_application (controller.app);

            //TODO: use dark theme universally across systems
            if (!controller.on_elementary) {
                Gtk.Settings.get_default ().set ("gtk-application-prefer-dark-theme", true);
            }

            // Set window properties
            this.set_default_size (controller.settings.window_width, controller.settings.window_height);
            this.window_position = Gtk.WindowPosition.CENTER;

            // Set up the close event
            this.delete_event.connect (on_window_closing);
            this.window_state_event.connect ((e) => {
                if(!ignore_window_state_change) {
                    on_window_state_changed (e.window.get_state ());
                } else {
                    unmaximize ();
                }
                ignore_window_state_change = false;
                return false;
            });
            
            
            
            info ("Creating video playback widgets.");
            
            // Create the drawing area for the video widget
            video_widget = new GtkClutter.Embed ();
            video_widget.use_layout_size = false;
            video_widget.button_press_event.connect (on_video_button_press_event);
            video_widget.button_release_event.connect (on_video_button_release_event);

            stage = (Clutter.Stage) video_widget.get_stage ();
            stage.background_color = {0, 0, 0, 0};
            stage.use_alpha = true;

            actor = new Clutter.Actor();
            var aspect_ratio = new ClutterGst.Aspectratio ();
            ((ClutterGst.Content) aspect_ratio).player = controller.player;
            actor.content = aspect_ratio;

            actor.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.WIDTH, 0));
            actor.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.HEIGHT, 0));
            stage.add_child (actor);

            // Set up all the video controls
            video_controls = new VideoControls ();
            video_controls.vexpand = true;
            video_controls.set_valign (Gtk.Align.END);
            video_controls.unfullscreen.connect (on_fullscreen_request);
            video_controls.play_toggled.connect (controller.play_pause);

            bottom_actor = new GtkClutter.Actor.with_contents (video_controls);
            stage.add_child (bottom_actor);

            var child1 = video_controls.get_child () as Gtk.Container;
            foreach(Gtk.Widget child in child1.get_children()) {
                child.parent.get_style_context ().add_class ("video-toolbar");
                child.parent.parent.get_style_context ().add_class ("video-toolbar");
            }

            video_widget.motion_notify_event.connect (on_motion_event);

            return_to_library = new Gtk.Button.with_label (_("Return to Library"));
            return_to_library.get_style_context ().add_class ("video-back-button");
            return_to_library.has_tooltip = true;
            return_to_library.tooltip_text = _("Return to Library");
            return_to_library.relief = Gtk.ReliefStyle.NONE;
            return_to_library.margin = 5;
            return_to_library.set_no_show_all (false);
            return_to_library.show ();

            return_to_library.clicked.connect (on_return_to_library);

            return_revealer = new Gtk.Revealer ();
            return_revealer.transition_type = Gtk.RevealerTransitionType.CROSSFADE;
            return_revealer.add (return_to_library);

            return_actor = new GtkClutter.Actor.with_contents (return_revealer);
            stage.add_child (return_actor);
            
            info ("Creating notebook.");

            notebook = new Gtk.Stack();
            notebook.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
            notebook.transition_duration = 200;

            info ("Creating welcome screen.");
            
            // Create a welcome screen and add it to the notebook (no matter if first run or not)
            welcome = new Granite.Widgets.Welcome (_("Welcome to Vocal"), _("Build Your Library By Adding Podcasts"));
            welcome.append(controller.on_elementary ? "preferences-desktop-online-accounts" : "applications-internet", _("Browse Podcasts"),
                 _("Browse through podcasts and choose some to add to your controller.library."));
            welcome.append("list-add", _("Add a New Feed"), _("Provide the web address of a podcast feed."));
            welcome.append("document-open", _("Import Subscriptions"),
                    _("If you have exported feeds from another podcast manager, import them here."));
            welcome.activated.connect(on_welcome);
            
            info ("Creating scrolled containers and album art views.");

            // Set up scrolled windows so that content will scoll instead of causing the window to expand
            directory_scrolled = new Gtk.ScrolledWindow (null, null);
            search_results_scrolled = new Gtk.ScrolledWindow(null, null);
            search_results_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            search_results_scrolled.add(search_results_box);
            
            all_podcasts_view = new AllPodcastsView();
            all_podcasts_view.on_podcast_selected.connect(on_child_activated);
            controller.library.on_unsubscribed_from_podcast.connect(() => {
                switch_visible_page(all_podcasts_view);
                populate_views();
            });
		    
            // Set up all the signals for the podcast view
            podcast_view = new PodcastView (controller);
            podcast_view.play_episode_requested.connect(play_different_track);
            
            podcast_view.download_episode_requested.connect(download_episode);
            podcast_view.download_all_requested.connect((episodes) => {
                foreach (var episode in episodes) {
                    download_episode(episode);
                }
            });
            
            podcast_view.enqueue_episode.connect(controller.library.enqueue_episode);

            podcast_view.mark_episode_as_played_requested.connect(controller.library.mark_episode_as_played);
            podcast_view.mark_multiple_episodes_as_played.connect(controller.library.mark_episodes_as_played);
            
            podcast_view.mark_episode_as_unplayed_requested.connect(controller.library.mark_episode_as_unplayed);
            podcast_view.mark_multiple_episodes_as_unplayed.connect(controller.library.mark_episodes_as_unplayed);

            podcast_view.mark_all_episodes_as_played_requested.connect(on_mark_as_played_request);
            
            podcast_view.delete_local_episode_requested.connect(on_episode_delete_request);
            podcast_view.delete_multiple_episodes.connect(controller.library.delete_local_episodes);

            podcast_view.on_unsubscribe_from_podcast.connect(on_remove_request);

            //  podcast_view.unplayed_count_changed.connect(on_unplayed_count_changed);
            podcast_view.on_new_cover_art_selected.connect(controller.library.set_new_local_album_art);
            podcast_view.go_back.connect(() => {
                switch_visible_page(all_podcasts_view);
            });
            //  podcast_view.on_hide_played.connect(controller.settings.toggle_hide_played);

            // Set up the box that gets displayed when importing from .OPML or .XML files during the first launch
            import_message_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 25);
            var import_h1_label = new Gtk.Label(_("Good Stuff is On Its Way"));
            var import_h3_label = new Gtk.Label(_("If you are importing several podcasts it can take a few minutes. Your controller.library will be ready shortly."));
            import_h1_label.get_style_context ().add_class("h1");
            import_h3_label.get_style_context ().add_class("h3");
            import_h1_label.margin_top = 200;
            import_message_box.add(import_h1_label);
            import_message_box.add(import_h3_label);
            var spinner = new Gtk.Spinner();
            spinner.active = true;
            spinner.start();
            import_message_box.add(spinner);

            // Add everything into the notebook (except for the iTunes store and search view)
            notebook.add_titled(welcome, "welcome", _("Welcome"));
            notebook.add_titled(import_message_box, "import", _("Importing"));
            notebook.add_titled(all_podcasts_view, "all", _("All Podcasts"));
            notebook.add_titled(podcast_view, "podcast_view", _("Details"));
            notebook.add_titled(video_widget, "video_player", _("Video"));
            
            bool show_complete_button = controller.first_run || controller.library_empty;
            
            info ("Creating directory view.");
            
            directory = new DirectoryView(controller.itunes, show_complete_button);
            directory.on_new_subscription.connect(controller.add_podcast_feed);
            directory.return_to_library.connect(on_return_to_library);
            directory.return_to_welcome.connect(() => {
                switch_visible_page(welcome);
            });
            directory_scrolled.add(directory);
            

            // Add the remaining widgets to the notebook. At this point, the gang's all here
            notebook.add_titled(directory_scrolled, "directory", _("Browse Podcast Directory"));
            notebook.add_titled(search_results_scrolled, "search", _("Search Results"));
            
            info("Creating toolbar.");

            // Create the toolbar
            toolbar = new Toolbar (controller.settings);
            toolbar.get_style_context ().add_class ("vocal-headerbar");
            toolbar.search_button.clicked.connect (on_show_search);

            // Change the player position to match scale changes
            toolbar.playback_box.scale_changed.connect (() => {
                controller.player.set_position (toolbar.playback_box.get_progress_bar_fill());
            });
            
            toolbar.check_for_updates_selected.connect (() => {
                controller.on_update_request ();
            });

            toolbar.add_podcast_selected.connect (() => {
                add_new_podcast ();
            });

            toolbar.import_podcasts_selected.connect (() => {
                import_podcasts();
            });

            toolbar.about_selected.connect (() => {
                controller.app.show_about (this);
            });

            toolbar.preferences_selected.connect (() => {
                settings_dialog = new SettingsDialog (controller.settings, this);
                settings_dialog.show_name_label_toggled.connect (on_show_name_label_toggled);
                settings_dialog.show_all ();
            });

            toolbar.refresh_selected.connect (controller.on_update_request);
            toolbar.play_pause_selected.connect (controller.play_pause);
            toolbar.seek_forward_selected.connect (controller.seek_forward);
            toolbar.seek_backward_selected.connect (controller.seek_backward);
            toolbar.playlist_button.clicked.connect(() => { queue_popover.show_all(); });

            toolbar.store_selected.connect (() => {
                switch_visible_page (directory_scrolled);
            });

            toolbar.export_selected.connect (export_podcasts);
            toolbar.downloads_selected.connect (show_downloads_popover);
            toolbar.shownotes_button.clicked.connect(() => { shownotes.show_all(); });

            // Repeat for the video playback box scale
            video_controls.progress_bar_scale_changed.connect (() => {
                controller.player.set_position (video_controls.progress_bar_fill);
            });
            
            this.set_titlebar(toolbar);
            
            
            info ("Creating show notes popover.");
            
            // Create the show notes popover
            shownotes = new ShowNotesPopover(toolbar.shownotes_button);
            
            info ("Creating downloads popover.");
            downloads = new DownloadsPopover(toolbar.download);
            downloads.closed.connect(() => {
                if(downloads.downloads.size < 1)
                    toolbar.hide_downloads_menuitem();
            });
            downloads.all_downloads_complete.connect(toolbar.hide_downloads_menuitem);

            info ("Creating queue popover.");
            // Create the queue popover
            queue_popover = new QueuePopover(toolbar.playlist_button);
            controller.library.queue_changed.connect(() => {
                queue_popover.set_queue(controller.library.queue);
            });
            queue_popover.set_queue(controller.library.queue);
            queue_popover.move_up.connect((e) => {
                controller.library.move_episode_up_in_queue(e);
                queue_popover.show_all();
            });
            queue_popover.move_down.connect((e) => {
                controller.library.move_episode_down_in_queue(e);
                queue_popover.show_all();
            });
            queue_popover.update_queue.connect((oldPos, newPos) => {
                controller.library.update_queue(oldPos, newPos);
                queue_popover.show_all();
            });

            queue_popover.remove_episode.connect((e) => {
                controller.library.remove_episode_from_queue(e);
                queue_popover.show_all();
            });
            queue_popover.play_episode_from_queue_immediately.connect(play_episode_from_queue_immediately);

            info ("Adding notebook to window.");
            current_widget = notebook;
            this.add (notebook);

            // Create the search box
            search_results_view = new SearchResultsView(controller.library);
            search_results_view.on_new_subscription.connect(controller.add_podcast_feed);
            search_results_view.return_to_library.connect(() => {
                switch_visible_page(previous_widget);
            });
            search_results_view.episode_selected.connect(on_search_popover_episode_selected);
            search_results_view.podcast_selected.connect(on_search_popover_podcast_selected);

            search_results_box.add(search_results_view);
            
             if(controller.open_hidden) {
                info("The app will open hidden in the background.");
                this.hide();
            }
            info("Window initialization complete.");
        }

        /*
         * Populates the three views (all, audio, video) from the contents of the controller.library
         */
        public async void populate_views() {

            SourceFunc callback = populate_views.callback;

            ThreadFunc<void*> run = () => {

            	if(!controller.currently_repopulating) {
            		controller.currently_repopulating = true;
    	            bool has_video = false;

                    // If it's not the first run or newly launched go ahead and remove all the widgets from the flowboxes
                    if(!controller.first_run && !controller.newly_launched) {
                        all_podcasts_view.clear();
                    }

    	            // If the program was just launched, check to see what the last played media was
    	            if(controller.newly_launched) {
                        current_widget = all_podcasts_view;

    	                if(controller.settings.last_played_media != null && controller.settings.last_played_media.length > 1) {

    	                    // Split the media into two different strings
    	                    string[] fields = controller.settings.last_played_media.split(",");
                            string podcast_name = fields[1];
                            string episode_title = fields[0];

                            Podcast podcast = controller.library.get_podcast_by_name(podcast_name);
                            if(podcast != null) {
                                Episode episode = podcast.find_episode_by_title(episode_title);
                                if(episode != null) {
                                    controller.current_episode = episode;
                                    toolbar.playback_box.set_info_title(controller.current_episode.title.replace("%27", "'"), controller.current_episode.parent.name.replace("%27", "'"));
                                    controller.track_changed(controller.current_episode.title, controller.current_episode.parent.name, controller.current_episode.parent.coverart_uri, (uint64) controller.player.duration);

                                    try {

                                        controller.player.set_episode(controller.current_episode);
                                        controller.player.set_position(controller.current_episode.last_played_position);
                                        shownotes.set_notes_text(episode.description);

                                    } catch(Error e) {
                                        warning(e.message);
                                    }

                                    if(controller.current_episode.last_played_position != 0) {
                                        toolbar.show_playback_box();
                                    } else {
                                        toolbar.hide_playback_box();
                                    }
                                }
                            }
    	                }
    	            }

    	            // Refill the library based on what is stored in the database (if it's not newly launched, in
    	            // which case it has already been filled)
    	            if(!controller.newly_launched){
    	                controller.library.refill_library();
    	            }

    	            // Clear flags since we have an established controller.library at this point
    	            controller.newly_launched = false;
    	            controller.first_run = false;
    	            controller.library_empty = false;

	                foreach(Podcast podcast in controller.library.podcasts) {
                        all_podcasts_view.add_podcast(podcast);
	                }

    	            controller.currently_repopulating = false;
            	}

                Idle.add((owned) callback);
                return null;
            };

            Thread.create<void*>(run, false);

            yield;

            // If the app is supposed to open hidden, don't present the window. Instead, hide it
            if(!controller.open_hidden && !controller.is_closing) {
                show_all();
            }
        }



        /*
         * When a user double-clicks and episode in the queue, remove it from the queue and
         * immediately begin playback
         */
        private void play_episode_from_queue_immediately(Episode e) {

            controller.current_episode = e;
            queue_popover.hide();
            // FIXME: Maybe the episode should remain in the queue until it has finished playing
            controller.library.remove_episode_from_queue(e);

            controller.play();

            // Set the shownotes, the media information, and update the last played media in the settings
            controller.track_changed(controller.current_episode.title, controller.current_episode.parent.name, controller.current_episode.parent.coverart_uri, (uint64)controller.player.duration);
            shownotes.set_notes_text(controller.current_episode.description);
            controller.settings.last_played_media = "%s,%s".printf(controller.current_episode.title, controller.current_episode.parent.name);
        }
        
        /*
         * Switches the current track and requests the newly selected track starts playing
         */
        private void play_different_track (Episode episode) {
            controller.current_episode = episode;

            controller.player.pause();
            controller.play();

            // Set the shownotes, the media information, and update the last played media in the settings
            controller.track_changed(controller.current_episode.title, controller.current_episode.parent.name, controller.current_episode.parent.coverart_uri, (uint64) controller.player.duration);
            shownotes.set_notes_text(controller.current_episode.description);
            controller.settings.last_played_media = "%s,%s".printf(controller.current_episode.title, controller.current_episode.parent.name);
        }


        /*
         * Handles request to download an episode, by showing the downloads menuitem and
         * requesting the download from the controller.library
         */
        public void download_episode(Episode episode) {
            toolbar.show_download_button();
            
            // Begin the process of downloading the episode (asynchronously)
            var details_box = controller.library.download_episode(episode);
            if(details_box == null) {
                return;
            }
            details_box.cancel_requested.connect(on_download_canceled);
            details_box.new_percentage_available.connect(() => {
                double overall_percentage = 1.0;

                foreach(DownloadDetailBox d in downloads.downloads) {
                    if(d.percentage > 0.0) {
                        overall_percentage *= d.percentage;
                    }
                }
            });

            downloads.add_download(details_box);
        }

        /*
         * Show a dialog to add a single feed to the controller.library
         */
        public void add_new_podcast() {
            add_feed = new AddFeedDialog(this, controller.on_elementary);
            add_feed.on_add_feed.connect(controller.add_podcast_feed);
            add_feed.show_all();
        }


        /*
         * Create a file containing the current controller.library subscription export
         */
        public void export_podcasts() {
            //Create a new file chooser dialog and allow the user to import the save configuration
            var file_chooser = new Gtk.FileChooserDialog ("Save Subscriptions to XML File",
                          this,
                          Gtk.FileChooserAction.SAVE,
                          _("Cancel"), Gtk.ResponseType.CANCEL,
                          _("Save"), Gtk.ResponseType.ACCEPT);

            var all_files_filter = new Gtk.FileFilter();
            all_files_filter.set_filter_name(_("All files"));
            all_files_filter.add_pattern("*");

            var opml_xml_filter = new Gtk.FileFilter();
            opml_xml_filter.set_filter_name(_("OPML and XML files"));
            opml_xml_filter.add_mime_type("application/xml");
            opml_xml_filter.add_mime_type("text/x-opml+xml");

            file_chooser.add_filter(opml_xml_filter);
            file_chooser.add_filter(all_files_filter);

            //Modal dialogs are sexy :)
            file_chooser.modal = true;

            //If the user selects a file, get the name and parse it
            if (file_chooser.run () == Gtk.ResponseType.ACCEPT) {
                string file_name = (file_chooser.get_filename ());
                controller.library.export_to_OPML(file_name);
            }

            //If the user didn't select a file, destroy the dialog
            file_chooser.destroy ();
        }


        /*
         * Choose a file to import to the controller.library
         */
        public void import_podcasts() {

            controller.currently_importing = true;

            var file_chooser = new Gtk.FileChooserDialog (_("Select Subscription File"),
                 this,
                 Gtk.FileChooserAction.OPEN,
                 _("Cancel"), Gtk.ResponseType.CANCEL,
                 _("Open"), Gtk.ResponseType.ACCEPT);

            var all_files_filter = new Gtk.FileFilter();
            all_files_filter.set_filter_name(_("All files"));
            all_files_filter.add_pattern("*");

            var opml_filter = new Gtk.FileFilter();
            opml_filter.set_filter_name(_("OPML files"));
            opml_filter.add_mime_type("text/x-opml+xml");

            file_chooser.add_filter(opml_filter);
            file_chooser.add_filter(all_files_filter);

            file_chooser.modal = true;

            int decision = file_chooser.run();
            string file_name = file_chooser.get_filename();

            file_chooser.destroy();

            //If the user selects a file, get the name and parse it
            if (decision == Gtk.ResponseType.ACCEPT) {

                toolbar.show_playback_box();

                // Hide the shownotes button
                toolbar.hide_shownotes_button();
                toolbar.hide_playlist_button();

                if(current_widget == welcome) {
                    switch_visible_page(import_message_box);
                }

                var loop = new MainLoop();
                controller.library.add_from_OPML(file_name, (obj, res) => {

                    bool success = controller.library.add_from_OPML.end(res);

                    if(success) {

                        if(!controller.player.playing)
                            toolbar.hide_playback_box();

                        // Is there now at least one podcast in the controller.library?
                        if(controller.library.podcasts.size > 0) {

                            // Make the refresh and export items sensitive now
                            toolbar.export_item.sensitive = true;

                            toolbar.show_shownotes_button();
                            toolbar.show_playlist_button();

                            populate_views();

                            if(current_widget == import_message_box) {
                                switch_visible_page(all_podcasts_view);
                            }

                            controller.library_empty = false;

                            show_all();
                        }

                    } else {

                        if(!controller.player.playing)
                            toolbar.hide_playback_box();

                        var add_err_dialog = new Gtk.MessageDialog(add_feed,
                            Gtk.DialogFlags.MODAL,Gtk.MessageType.ERROR,
                            Gtk.ButtonsType.OK, "");
                            add_err_dialog.response.connect((response_id) => {
                                add_err_dialog.destroy();
                            });
                            
                        // Determine if it was a network issue, or just a problem with the feed
                        
                        bool network_okay = Utils.confirm_internet_functional();
                        
                        string error_message;
                        
                        if(network_okay) {
                            error_message = _("Please check that you selected the correct file and that it is not corrupted.");
                        } else {
                            error_message = _("There seems to be a problem with your internet connection. Make sure you are online and then try again.");
                        }

                        var error_img = new Gtk.Image.from_icon_name ("dialog-error", Gtk.IconSize.DIALOG);
                        add_err_dialog.set_transient_for(this);
                        add_err_dialog.text = _("Error Importing from File");
                        add_err_dialog.secondary_text = error_message;
                        add_err_dialog.set_image(error_img);
                        add_err_dialog.show_all();
                    }

                    controller.currently_importing = false;

                    if(controller.player.playing) {
                        toolbar.playback_box.set_info_title(controller.current_episode.title.replace("%27", "'"), controller.current_episode.parent.name.replace("%27", "'"));
                        video_controls.set_info_title(controller.current_episode.title.replace("%27", "'"), controller.current_episode.parent.name.replace("%27", "'"));
                    }

                    loop.quit();
                });
                loop.run();

                file_chooser.destroy();
            }
        }


        /*
         * UI-related methods
         */

        /*
         * Called when a podcast is selected from an iconview. Creates and displays a new window containing
         * the podcast and episode information
         */
        public void show_details (Podcast current_podcast) {
            podcast_view.set_podcast(current_podcast);
            switch_visible_page(podcast_view);
        }


        /*
         * Shows the downloads popover
         */
        public void show_downloads_popover() {
            this.downloads.show_all();
        }


        /*
         * Called when a different widget needs to be displayed in the notebook
         */
         public void switch_visible_page(Gtk.Widget widget) {

            if(current_widget != widget)
                previous_widget = current_widget;

            if (widget == all_podcasts_view) {
                notebook.set_visible_child(all_podcasts_view);
                current_widget = all_podcasts_view;
            }
            else if (widget == podcast_view) {
                notebook.set_visible_child(podcast_view);
                current_widget = podcast_view;
            }
            else if (widget == video_widget) {
                notebook.set_visible_child(video_widget);
                current_widget = video_widget;
            }
            else if (widget == import_message_box) {
                notebook.set_visible_child(import_message_box);
                current_widget = import_message_box;
            }
            else if (widget == search_results_scrolled) {
                notebook.set_visible_child(search_results_scrolled);
                current_widget = search_results_scrolled;
            }
            else if (widget == directory_scrolled) {
                notebook.set_visible_child(directory_scrolled);
                current_widget = directory_scrolled;
            }
            else if (widget == welcome) {
                notebook.set_visible_child(welcome);
                current_widget = welcome;
            }
            else {
                info("Attempted to switch to a notebook page that didn't exist. This is likely a bug and might cause issues.");
            }
         }


        /*
         * Signal handlers and callbacks
         */


        /*
         * Called when the player attempts to play media but the necessary Gstreamer plugins are not installed.
         * Prompts user to install the plugins and then proceeds to handle the installation. Playback begins
         * once plugins are installed.
         */
        public void on_additional_plugins_needed(Gst.Message install_message) {
            warning("Required GStreamer plugins were not found. Prompting to install.");
            missing_dialog = new Gtk.MessageDialog(this, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO,
                 _("Additional plugins are needed to play media. Would you like for Vocal to install them for you?"));

            missing_dialog.response.connect ((response_id) => {
                switch (response_id) {
                    case Gtk.ResponseType.YES:
                        missing_dialog.destroy();
                        var plugins_are_installing = true;

                        var installer = Gst.PbUtils.missing_plugin_message_get_installer_detail (install_message);
                        var context = new Gst.PbUtils.InstallPluginsContext ();

                         // Since we can't do anything else anyways, go ahead and install the plugins synchronously
                         Gst.PbUtils.InstallPluginsReturn ret = Gst.PbUtils.install_plugins_sync ({ installer }, context);
                         if(ret == Gst.PbUtils.InstallPluginsReturn.SUCCESS) {
                            info("Plugins have finished installing. Updating GStreamer registry.");
                            Gst.update_registry ();
                            plugins_are_installing = false;

                            info("GStreamer registry updated, attempting to start playback using the new plugins...");

                            // Reset the controller.player
                            controller.player.current_episode = null;

                            controller.play();
                         }

                        break;
                    case Gtk.ResponseType.NO:
                        break;
                }

                missing_dialog.destroy();
            });
            missing_dialog.show ();
        }


        /*
         * Handles requests to add individual podcast feeds (either from welcome screen or
         * the add feed menuitem
         */
        public void on_add_podcast_feed(string feed) {
            controller.add_podcast_feed(feed);
        }


        /*
         * Called whenever a child is activated (selected) in one of the three flowboxes.
         */
        public void on_child_activated(Podcast podcast) {
            show_details(podcast);
        }

         private void on_download_canceled(Episode episode) {

            if(podcast_view != null && episode.parent == podcast_view.podcast) {

                // Get the index for the episode in the list
                //  int index = podcast_view.get_box_index_from_episode(episode);
            }
        }

        public void on_download_finished(Episode episode) {

            if (podcast_view != null && episode.parent == podcast_view.podcast) {
                //  podcast_view.shownotes.hide_download_button();
            }
        }

        public void on_delete_multiple_episodes(Gee.ArrayList<Episode> episodes) {
            foreach(Episode episode in episodes) {
                on_episode_delete_request(episode);
            }
        }

        private void on_episode_delete_request(Episode episode) {
            controller.library.delete_local_episode(episode);
            //  podcast_view.on_single_delete(episode);
        }

		/*
		 * Called when the app needs to go fullscreen or unfullscreen
		 */
        public void on_fullscreen_request() {

            if(fullscreened) {
                unfullscreen();
                video_controls.set_reveal_child(false);
                fullscreened = false;
                ignore_window_state_change = true;
            } else {
                fullscreen();
                fullscreened = true;
            }
        }

        public void on_import_status_changed(int current, int total, string title) {
            show_all();
            toolbar.playback_box.set_message_and_percentage("Adding feed %d/%d: %s".printf(current, total, title), (double)((double)current/(double)total));
        }


        /*
         * Called when the user requests to mark a podcast as played from the library via the right-click menu
         */
        public void on_mark_as_played_request() {

            if(all_podcasts_view.selected_podcast != null) {
                Gtk.MessageDialog msg = new Gtk.MessageDialog (this, Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING, Gtk.ButtonsType.YES_NO,
                     _("Are you sure you want to mark all episodes from '%s' as played?".printf(GLib.Markup.escape_text(controller.highlighted_podcast.name.replace("%","%%")))));

                var image = new Gtk.Image.from_icon_name("dialog-question", Gtk.IconSize.DIALOG);
                msg.image = image;
                msg.image.show_all();

			    msg.response.connect ((response_id) => {
			        switch (response_id) {
				        case Gtk.ResponseType.YES:
                            controller.library.mark_all_as_played_async(all_podcasts_view.selected_podcast);
					        break;
				        case Gtk.ResponseType.NO:
					        break;
			        }

			        msg.destroy();
		        });
		        msg.show ();
	        }
        }

		/*
		 * Called when the user moves the cursor when a video is playing
		 */
        private bool on_motion_event(Gdk.EventMotion e) {

            // Figure out if you should just move the window
            if (mouse_primary_down) {
                mouse_primary_down = false;
                this.begin_move_drag (Gdk.BUTTON_PRIMARY,
                    (int)e.x_root, (int)e.y_root, e.time);
                
            } else {

                // Show the cursor again
                this.get_window ().set_cursor (null);

                bool hovering_over_headerbar = false,
                hovering_over_return_button = false,
                hovering_over_video_controls = false;

                int min_height, natural_height;
                video_controls.get_preferred_height(out min_height, out natural_height);


                // Figure out whether or not the cursor is over the video bar at the bottom
                // If so, don't actually hide the cursor
                if (fullscreened && e.y < natural_height) {
                    hovering_over_video_controls = true;
                } else {
                    hovering_over_video_controls = false;
                }


                // e.y starts at 0.0 (top) and goes for however long
                // If < 10.0, we can assume it's above the top of the video area, and therefore
                // in the headerbar area
                if (!fullscreened && e.y < 10.0) {
                    hovering_over_headerbar = true;
                }


                if (hiding_timer != 0) {
                    Source.remove (hiding_timer);
                }

                if(current_widget == video_widget) {

                    hiding_timer = GLib.Timeout.add (2000, () => {

                        if(current_widget != video_widget)
                        {
                            this.get_window ().set_cursor (null);
                            return false;
                        }

                        if(!fullscreened && (hovering_over_video_controls || hovering_over_return_button)) {
                            hiding_timer = 0;
                            return true;
                        }

                        else if (hovering_over_video_controls || hovering_over_return_button) {
                            hiding_timer = 0;
                            return true;
                        }

                        video_controls.set_reveal_child(false);
                        return_revealer.set_reveal_child(false);

                        if(controller.player.playing && !hovering_over_headerbar) {
                            this.get_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.BLANK_CURSOR));
                        }

                        return false;
                    });


                    if(fullscreened) {
                        bottom_actor.width = stage.width;
                        bottom_actor.y = stage.height - natural_height;
                        video_controls.set_reveal_child(true);
                    }
                    return_revealer.set_reveal_child(true);

                }
            }

            return false;
        }

        public void on_remove_request(Podcast podcast) {
            Gtk.MessageDialog msg = new Gtk.MessageDialog (this, Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING, Gtk.ButtonsType.NONE,
                _("Are you sure you want to remove '%s' from your library?"), podcast.name.replace("%27", "'"));

            msg.add_button (_("No"), Gtk.ResponseType.NO);
            var delete_button = msg.add_button(_("Yes"), Gtk.ResponseType.YES) as Gtk.Button;
            delete_button.get_style_context().add_class("destructive-action");

            var image = new Gtk.Image.from_icon_name("dialog-warning", Gtk.IconSize.DIALOG);
            msg.image = image;
            msg.image.show_all();
            msg.response.connect ((response_id) => {
                switch (response_id) {
                    case Gtk.ResponseType.YES:
                        controller.library.unsubscribe_from_podcast(podcast);
                        break;
                    case Gtk.ResponseType.NO:
                        break;
                }

                msg.destroy();
            });
            msg.show ();
        }


        /*
         * Called when the video needs to be hidden and the controller.library shown again
         */
        public void on_return_to_library() {

            // If fullscreen, first exit fullscreen so you won't be "trapped" in fullscreen mode
            if(fullscreened)
                on_fullscreen_request();

            // Since we can't see the video any more pause playback if necessary
            if(current_widget == video_widget && controller.player.playing)
                controller.pause();

            if(previous_widget == directory_scrolled || previous_widget == search_results_scrolled)
                previous_widget = all_podcasts_view;
            switch_visible_page(previous_widget);


            // Make sure the cursor is visible again
            this.get_window ().set_cursor (null);
        }

         /*
          * Called when the user clicks on a podcast in the search popover
          */
         private void on_search_popover_podcast_selected(Podcast podcast_to_select) {

            all_podcasts_view.select_podcast(podcast_to_select);
            show_details(podcast_to_select);
            controller.highlighted_podcast = podcast_to_select;

            //  this.current_episode_art = a;
         }


         /*
          * Called when the user clickson an episode in the search popover
          */
         private void on_search_popover_episode_selected(Podcast podcast, Episode episode) {
            on_search_popover_podcast_selected(podcast);
            podcast_view.select_episode(episode);
         }


        /*
         * Shows a full search results listing
         */
        public void on_show_search() {
            switch_visible_page(search_results_scrolled);
            show_all();
        }


        /*
         * Called when the user toggles the show name label setting.
         * Calls the show/hide label method for every cover art.
         */
        public void on_show_name_label_toggled() {
            if(controller.settings.show_name_label) {
                //  foreach(CoverArt a in all_art) {
                //      a.show_name_label();
                //  }
            } else {
                //  foreach(CoverArt a in all_art) {
                //      a.hide_name_label();
                //  }
            }
        }


        /*
         * Called when the player finishes a stream
         */
        public void on_stream_ended() {

            // hide the playback box and set the image on the pause button to play
            toolbar.hide_playback_box();

            var playpause_image = new Gtk.Image.from_icon_name("media-playback-start-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
            toolbar.set_play_pause_image(playpause_image);

            // If there is a video showing, return to the controller.library view
            if(controller.current_episode.parent.content_type == MediaType.VIDEO) {
                on_return_to_library();
            }

            controller.player.current_episode.last_played_position = 0;
            controller.library.set_episode_playback_position(controller.player.current_episode);

            controller.playback_status_changed("Stopped");

            controller.current_episode = controller.library.get_next_episode_in_queue();

            if(controller.current_episode != null) {

                controller.play();

                // Set the shownotes, the media information, and update the last played media in the settings
                controller.track_changed(controller.current_episode.title, controller.current_episode.parent.name, controller.current_episode.parent.coverart_uri, (uint64) controller.player.duration);
                shownotes.set_notes_text(controller.current_episode.description);
                controller.settings.last_played_media = "%s,%s".printf(controller.current_episode.title, controller.current_episode.parent.name);
            } else {
                controller.player.playing = false;
            }

        }


        /*
         * Requests the app to be taken fullscreen if the video widget
         * is double-clicked
         */
        private bool on_video_button_press_event(Gdk.EventButton e) {
            mouse_primary_down = true;
            if(e.type == Gdk.EventType.2BUTTON_PRESS) {
                on_fullscreen_request();
            }

            return false;
        }

        private bool on_video_button_release_event(Gdk.EventButton e) {
            mouse_primary_down = false;
            return false;
        }

        /*
         * Handles responses from the welcome screen
         */
        private void on_welcome(int index) {
            switch(index) {
                case 0: // Browse podcasts
                    switch_visible_page(directory_scrolled);
                    // Set the controller.library as the previous widget for return_to_library to work
                    previous_widget = all_podcasts_view;
                    break;
                case 1: // Add new feed
                    add_new_podcast();
                    break;
                case 2: // Import from OPML
                    // The import podcasts method will handle any errors
                    import_podcasts();
                    break;
                default:
                    break;
            } 
        }


        /*
         * Saves the window height and width before closing, and decides whether to close or minimize
         * based on whether or not a track is currently playing
         */
        private bool on_window_closing() {

            controller.is_closing = true;

        	// If flagged to quit immediately, return true to go ahead and do that.
        	// This flag is usually only set when the user wants to exit while downloads
        	// are active
        	if(controller.should_quit_immediately) {
        		return false;
        	}

            int width, height;
            this.get_size(out width, out height);
            controller.settings.window_height = height;
            controller.settings.window_width = width;



            // Save the playback position
            if(controller.player.current_episode != null) {
                stdout.printf("Setting the last played position to %s\n", controller.player.current_episode.last_played_position.to_string());
                if(controller.player.current_episode.last_played_position != 0)
                    controller.library.set_episode_playback_position(controller.player.current_episode);
            }

            // If an episode is currently playing, hide the window
            if(controller.player.playing) {
                this.hide();
                return true;
            } else if(downloads != null && downloads.downloads.size > 0) {

            	//If there are downloads verify that the user wishes to exit and cancel the downloads
            	var downloads_active_dialog = new Gtk.MessageDialog(this, Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING, Gtk.ButtonsType.YES_NO, _("Vocal is currently downloading episodes. Exiting will cause the downloads to be canceled. Are you sure you want to exit?"));
            	downloads_active_dialog.response.connect ((response_id) => {
            		downloads_active_dialog.destroy();
					if(response_id == Gtk.ResponseType.YES) {
						controller.should_quit_immediately = true;
						this.close();
					}
				});
				downloads_active_dialog.show();
				return true;
            } else {
            	// If no downloads are active and nothing is playing,
            	// return false to allow other handlers to close the window.
            	return false;
        	}
        }

		/*
		 * Handler for when the window state changes
		 */
        private void on_window_state_changed(Gdk.WindowState state) {

            if(controller.open_hidden) {
                show_all();
                controller.open_hidden = false;
            }

            if(ignore_window_state_change)
                return;

            bool maximized = (state & Gdk.WindowState.MAXIMIZED) == 0;

            if(!maximized && !fullscreened && current_widget == video_widget) {
                on_fullscreen_request();
            }
        }
    }
}
