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

using Gee;

namespace Vocal {
    public class Podcast : Object {
        
        public signal void unplayed_episodes_updated();
        public signal void new_cover_art_set();
        
        public  ArrayList<Episode> episodes = null;
        public string name                  = null;
        public string feed_uri              = null;
        public string remote_art_uri        = null;   // the web link to the album art if local is unavailable
        public string local_art_uri         = null;   // where the locally cached album art is located      
        public string description           = null;
        private int _unplayed_count         = 0;
        public int unplayed_count {
            get { return _unplayed_count; }
        }
        public MediaType   content_type;
        
        /*
        * Gets and sets the coverart, whether it's from a remote source
        * or locally cached.
        */
        public string coverart_uri {
            
            //the album art is saved locally, return that path. Otherwise, return main album art URI
            get {
                if(local_art_uri != null) {
                    GLib.File local_art = GLib.File.new_for_uri(local_art_uri);
                    if(local_art.query_exists()) {
                        return local_art_uri;
                    }
                } else if(remote_art_uri != null) {
                    GLib.File remote_art = GLib.File.new_for_uri(remote_art_uri);
                    if(remote_art.query_exists()) {
                        return remote_art_uri;
                    }
                }
                // In rare instances where album art is not available at all, provide a "missing art" image to use
                // in library view
                return "resource:///com/github/needle-and-thread/vocal/missing.png";
            }
            
            // If the URI begins with "file://" set local uri, otherwise set the remote uri
            set {
                if("http://" in value.down() || "https://" in value.down() ) {
                    remote_art_uri = value.replace("%27", "'");
                } else {
                    local_art_uri = "file://" + value.replace("%27", "'");
                }

                new_cover_art_set();
            }
        }
        
        public Podcast () {
            episodes = new ArrayList<Episode>();
            content_type = MediaType.UNKNOWN;
        }

        public Podcast.with_name(string name) {
            this();
            this.name = name;
        }
            
        public void add_episodes(Gee.ArrayList<Episode> episodes) {
            foreach (var episode in episodes) {
                this.episodes.add(episode);
                episode.played_status_updated.connect(() => {
                    recount_unplayed_episodes();
                });
            }
        
            recount_unplayed_episodes();
        }
        
        public void add_episode(Episode new_episode) {
            episodes.add(new_episode);
            
            recount_unplayed_episodes();
            new_episode.played_status_updated.connect(() => {
                recount_unplayed_episodes();
            });
        }
        
        public int episode_count() {
            return episodes.size;
        }
        
        private void recount_unplayed_episodes() {
            int unplayed = 0;
            foreach (var episode in episodes) {
                if(episode.status == EpisodeStatus.UNPLAYED) {
                    unplayed++;
                }
            }
            
            if(unplayed != _unplayed_count) {
                _unplayed_count = unplayed;
                unplayed_episodes_updated();
            }
        }
        
        // FIXME: Some podcasts have multiple episodes with one name.
        public Episode? find_episode_by_title(string title) {
            foreach (var episode in episodes) {
                if(episode.title == title) {
                    return episode;
                }
            }
            
            info("No episode found in podcast %s with title %s\n", name, title);
            return null;
        }
    }
    
    
    /*
    * The possible types of media that a podcast might contain, generally either audio or video.
    */
    public enum MediaType {
        AUDIO, VIDEO, UNKNOWN;
        
        public string to_string () {
            switch (this) {
                case MediaType.AUDIO:
                return "audio";
                case MediaType.VIDEO:
                return "video";
                default:
                return "unknown";
            }
        }
        
        public static MediaType from_string (string str) {
            if (str == "audio") {
                return MediaType.AUDIO;
            } else if (str == "video") {
                return MediaType.VIDEO;
            } else {
                return MediaType.UNKNOWN;
            }
        }
    }
    
}
