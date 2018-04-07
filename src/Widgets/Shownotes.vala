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

	public class Shownotes : Gtk.ScrolledWindow {

		public signal void on_queue_episode(Episode episode);
		public signal void play_episode(Episode episode);
		public signal void on_download_episode(Episode episode);
		public signal void marked_as_played(Episode episode);
		public signal void marked_as_unplayed(Episode episode);
		public signal void copy_shareable_link(Episode episode);
		public signal void send_tweet(Episode episode);
		public signal void copy_direct_link(Episode episode);

		private Gtk.Button play_button;
		private Gtk.Button queue_button;
		private Gtk.Button download_button;
		private Gtk.Button share_button;
		private Gtk.Button mark_as_played_button;
		private Gtk.Button mark_as_new_button;
		private Gtk.Button delete_button;
		private Episode episode = null;

		private Gtk.MenuItem shareable_link;
		private Gtk.MenuItem tweet;
		private Gtk.MenuItem link_to_file;

		private Gtk.Label title_label;
		private Gtk.Label date_label;
		private Gtk.Box controls_box;
		private Gtk.Label shownotes_label;

		public Shownotes () {
			var content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

			shownotes_label = new Gtk.Label ("");
			shownotes_label.margin = 12;
			shownotes_label.halign = Gtk.Align.START;
			shownotes_label.valign = Gtk.Align.START;
			shownotes_label.xalign = 0;
			shownotes_label.wrap = true;

			controls_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			controls_box.get_style_context().add_class("toolbar");
			controls_box.get_style_context().add_class("podcast-view-toolbar");
			controls_box.height_request = 30;

			mark_as_played_button = new Gtk.Button.from_icon_name("object-select-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
			mark_as_played_button.has_tooltip = true;
			mark_as_played_button.relief = Gtk.ReliefStyle.NONE;
			mark_as_played_button.tooltip_text = _("Mark this episode as played");
			mark_as_played_button.clicked.connect(() => {
				marked_as_played(this.episode);
			});

			mark_as_new_button = new Gtk.Button.from_icon_name("starred-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
			mark_as_new_button.has_tooltip = true;
			mark_as_new_button.relief = Gtk.ReliefStyle.NONE;
			mark_as_new_button.tooltip_text = _("Mark this episode as new");
			mark_as_new_button.clicked.connect(() => {
				marked_as_unplayed(this.episode);
			});

			download_button = new Gtk.Button.from_icon_name(Utils.check_elementary() ? "browser-download-symbolic" : "document-save-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
			download_button.has_tooltip = true;
			download_button.relief = Gtk.ReliefStyle.NONE;
			download_button.tooltip_text = _("Download episode");
			download_button.clicked.connect(() => {
				on_download_episode(this.episode);
			});

			share_button = new Gtk.Button.from_icon_name(Utils.check_elementary() ? "send-to-symbolic" : "emblem-shared-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
			share_button.has_tooltip = true;
			share_button.relief = Gtk.ReliefStyle.NONE;
			share_button.tooltip_text = _("Share this episode");
			share_button.button_press_event.connect((e) => {
				var share_menu = new Gtk.Menu();
				shareable_link = new Gtk.MenuItem.with_label(_("Copy shareable link"));
				tweet = new Gtk.MenuItem.with_label(_("Send a Tweet…"));
				link_to_file = new Gtk.MenuItem.with_label(_("Copy the direct episode link"));

				shareable_link.activate.connect(() => { 
					copy_shareable_link(this.episode); 
				});
				tweet.activate.connect(() => { 
					send_tweet(this.episode); 
				});
				link_to_file.activate.connect(() => {
					copy_direct_link(this.episode); 
				});

				share_menu.add(shareable_link);
				share_menu.add(tweet);
				share_menu.add(new Gtk.SeparatorMenuItem());
				share_menu.add(link_to_file);
				share_menu.attach_to_widget(share_button, null);
				share_menu.show_all();
				share_menu.popup(null, null, null, e.button, e.time);
				return true;
			});

			controls_box.pack_start(mark_as_played_button, false, false, 0);
			controls_box.pack_start(mark_as_new_button, false, false, 0);
			controls_box.pack_start(download_button, false, false, 0);
			controls_box.pack_end(share_button, false, false, 0);

			title_label = new Gtk.Label("");
			title_label.get_style_context().add_class("h3");
			title_label.wrap = true;
			title_label.wrap_mode = Pango.WrapMode.WORD;
			title_label.margin_top = 20;
			title_label.margin_bottom = 6;
			title_label.margin_left = 12;
			title_label.halign = Gtk.Align.START;
			title_label.set_property("xalign", 0);

			date_label = new Gtk.Label("");
			date_label.margin_bottom = 12;
			date_label.margin_left = 12;
			date_label.halign = Gtk.Align.START;
			title_label.set_property("xalign", 0);

			play_button = new Gtk.Button.with_label("Play this episode");
			play_button.clicked.connect(() => {
				play_episode(this.episode);
			});
			queue_button = new Gtk.Button.from_icon_name("list-add-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
			queue_button.has_tooltip = true;
			queue_button.tooltip_text = _("Add this episode to the up next list");
			queue_button.clicked.connect(() => {
				on_queue_episode(this.episode);
			});

			var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5);
			button_box.pack_start(play_button, false, false, 0);
			button_box.pack_start(queue_button, false, false, 0);
			button_box.margin_bottom = 20;
			button_box.margin_left = 12;

			var summary_label = new Gtk.Label(_("<b>Summary</b>"));
			summary_label.use_markup = true;
			summary_label.margin_left = 12;
			summary_label.margin_bottom = 6;
			summary_label.halign = Gtk.Align.START;

			content_box.pack_start(controls_box, false, false, 0);
			content_box.pack_start(title_label, false, false, 0);
			content_box.pack_start(date_label, false, false, 0);
			content_box.pack_start(button_box, false, false, 0);
			content_box.pack_start(summary_label, false, false, 0);
			content_box.pack_start(shownotes_label, true, true, 0);

			this.add (content_box);
		}

		public void set_episode(Episode episode) {
			if(this.episode == episode) {
				return;
			}

			this.episode = episode;
			set_title(episode.title);
			set_html(episode.description != "(null)" ? Utils.html_to_markup(episode.description) : _("No show notes available."));
			set_date(episode.datetime_released);

			update_download_button_state();
			episode.download_status_changed.connect(() => {
				update_download_button_state();
			});

			update_played_status();
			episode.played_status_updated.connect(() => {
				update_played_status();
			});

			show_all();
		}

		private void set_html(string html) {
			shownotes_label.label = html;
			shownotes_label.use_markup = true;
			show_all();
		}

		private void update_download_button_state() {
			if(episode.download_status == DownloadStatus.DOWNLOADED) {
				hide_download_button();
			} else {
				show_download_button();
			}
		}

		private void show_download_button() {
			download_button.set_no_show_all(false);
			download_button.show();
		}

		private void hide_download_button() {
			download_button.set_no_show_all(true);
			download_button.hide();
		}

		private void set_title(string title) {
			title_label.set_text(title.replace("%27", "'"));
		}

		private void set_date(GLib.DateTime date) {
			date_label.set_text(date.format("%x"));
		}

		private void update_played_status() {
			if(episode.status == EpisodeStatus.PLAYED) {
				show_mark_as_new_button();
			} else {
				show_mark_as_played_button();
			}
		}

		private void show_mark_as_new_button () {
			mark_as_played_button.no_show_all = true;
			mark_as_played_button.hide ();

			mark_as_new_button.no_show_all = false;
			mark_as_new_button.show ();
		}

		private void show_mark_as_played_button () {
			mark_as_played_button.no_show_all = false;
			mark_as_played_button.show ();

			mark_as_new_button.no_show_all = true;
			mark_as_new_button.hide ();
		}
	}
}
