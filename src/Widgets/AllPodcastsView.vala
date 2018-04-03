namespace Vocal { 
    public class AllPodcastsView : Gtk.ScrolledWindow {
        public signal void on_podcast_selected(Podcast podcast);

        private Podcast _selected_podcast = null;
        public Podcast selected_podcast {
            get { return _selected_podcast; }
        }
        private Gtk.FlowBox podcast_flowbox;
        private GLib.ListStore podcast_model = new GLib.ListStore(typeof(Podcast));

        public AllPodcastsView() {
            podcast_flowbox = new Gtk.FlowBox();
            podcast_flowbox.bind_model(podcast_model, create_cover_art_box);
            podcast_flowbox.get_style_context().add_class("notebook-art");
            podcast_flowbox.selection_mode = Gtk.SelectionMode.SINGLE;
            podcast_flowbox.activate_on_single_click = true;
            podcast_flowbox.valign = Gtk.Align.FILL;
            podcast_flowbox.homogeneous = true;
            podcast_flowbox.child_activated.connect((flow_box_child) => {
                var selected_podcast = this.podcast_model.get_item(flow_box_child.get_index()) as Podcast;
                on_podcast_selected(selected_podcast);
                _selected_podcast = selected_podcast;
            });

            add(podcast_flowbox);
        }

        private Gtk.Widget create_cover_art_box(Object item) {
            Podcast podcast = item as Podcast;

            CoverArt cover_art = new CoverArt(podcast, true);
            cover_art.get_style_context().add_class("coverart");
            //  cover_art.halign = Gtk.Align.START;
            cover_art.halign = Gtk.Align.CENTER;
            cover_art.valign = Gtk.Align.START;

            return cover_art;
        }

        public void add_podcast(Podcast podcast) {
            podcast_model.append(podcast);
        }

        public void clear() {
            podcast_model.remove_all();
        }

        public void select_podcast(Podcast podcast_to_select) {
            for(int i = 0; i < podcast_model.get_n_items(); i++) {
                Podcast podcast = podcast_model.get_item(i) as Podcast;

                if(podcast_to_select.name == podcast.name) {
                    //  all_flowbox.unselect_all();
                    podcast_flowbox.select_child(podcast_flowbox.get_child_at_index(i));
                    break;
                }
            }
        }
    }
}