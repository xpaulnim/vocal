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

namespace Vocal {
    
    public class AddFeedDialog : Gtk.Dialog {
        
        public signal void on_add_feed(string feed);
        
        private	Gtk.Entry 	entry;
        private	Gtk.Button 	add_feed_button;
        
        public AddFeedDialog(Window parent, bool? using_elementary = true) {
            set_default_response(Gtk.ResponseType.OK);
            set_size_request(500, 150);
            set_modal(true);
            set_transient_for(parent);
            set_attached_to(parent);
            set_resizable(false);
            get_action_area().margin = 7;
            title = _("Add New Podcast");
            
            var add_label = new Gtk.Label(_("<b>Add a new podcast feed to the library</b>"));
            add_label.use_markup = true;
            add_label.set_property("xalign", 0);
            
            entry = new Gtk.Entry();
            entry.placeholder_text = _("Podcast feed web address");
            entry.activates_default = false;
            entry.margin = 12;
            entry.changed.connect(() => {
                if(entry.text.length > 0) {
                    add_feed_button.sensitive = true;
                } else {
                    add_feed_button.sensitive = false;
                }
            });
            entry.activate.connect(() => {
                add_feed();
            });
            
            Gtk.Image add_img = null; 
            if (using_elementary) { 
                add_img =  new Gtk.Image.from_icon_name ("list-add-symbolic", Gtk.IconSize.DIALOG);
            } else {
                add_img = new Gtk.Image.from_icon_name ("list-add", Gtk.IconSize.DIALOG); 
            }
            add_img.margin_right = 12;
            
            var content_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            content_box.margin_right = 12;
            content_box.margin_left = 12;
            content_box.add(add_img);
            content_box.add(add_label);
            
            add_button (_("Cancel"), Gtk.ResponseType.CANCEL);
            
            add_feed_button = add_button(_("Add Podcast"), Gtk.ResponseType.OK) as Gtk.Button;
            add_feed_button.get_style_context().add_class("suggested-action");
            add_feed_button.sensitive = false;
            //  add_feed_button.clicked.connect(add_feed);
            
            get_content_area().add(content_box);
            get_content_area().add(entry);
            
            response.connect ((response_id) => {
                switch (response_id) {
                    case Gtk.ResponseType.YES:
                    add_feed();
                    break;
                    case Gtk.ResponseType.NO:
                    break;
                }
                
                destroy();
            });
        }
        
        private void add_feed() {
            // TODO: Validate url before triggering signal and closing dialog.
            if(entry.text.length > 0) {
                info("got url %s", entry.get_text());
                on_add_feed(entry.get_text());
                destroy();
            }
        }
    }
}
