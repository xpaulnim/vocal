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
using Gst;
using GLib;
using Sqlite;


namespace Vocal {


    public errordomain VocalLibraryError {
        ADD_ERROR, IMPORT_ERROR, MISSING_URI;
    }


    public class Library {

        public signal void on_unsubscribed_from_podcast();
        
		// Fired when a download completes
        public signal void	download_finished(Episode episode);

        // Fired when there is an update during import
        public signal void 	import_status_changed(int current, int total, string name);

        private signal void new_episode_count_changed();

        // Fired when the queue changes
        public signal void queue_changed();

        public ArrayList<Podcast> podcasts;		// Holds all the podcasts in the library

        private Sqlite.Database db;				// The database

        private string db_location = null;
        private string vocal_config_dir = null;
        private string db_directory = null;
        private string local_library_path;

#if HAVE_LIBUNITY
        private Unity.LauncherEntry launcher;
#endif

        private FeedParser parser;				// Parser for parsing feeds
		private VocalSettings settings;			// Vocal's settings

        Episode downloaded_episode = null;

        private int batch_download_count = 0;
        private bool batch_notification_needed = false;

        public Gee.ArrayList<Episode> queue = new Gee.ArrayList<Episode>();

        private Controller controller;

        public Library(Controller controller) {

            this.controller = controller;

            vocal_config_dir = GLib.Environment.get_user_config_dir() + """/vocal""";
            this.db_directory = vocal_config_dir + """/database""";
            this.db_location = this.db_directory + """/vocal.db""";

            this.podcasts = new ArrayList<Podcast>();

            settings = VocalSettings.get_default_instance();

            // Set the local library path (and replace ~ with the absolute home directory if need be)
            local_library_path = settings.library_location.replace("~", GLib.Environment.get_home_dir());

            parser = new FeedParser();

#if HAVE_LIBUNITY
            launcher = Unity.LauncherEntry.get_for_desktop_id("vocal.desktop");
            launcher.count = 0;
#endif

            new_episode_count_changed.connect(set_new_badge);
        }

        public Podcast? get_podcast_by_name(string name) {
            foreach (var podcast in podcasts) {
                if(podcast.name == name) {
                    return podcast;
                }
            }

            info("No podcast found matching %s\n", name);
            return null;
        }

        public async bool add_from_OPML(string path) {

            bool successful = true;

            SourceFunc callback = add_from_OPML.callback;

            ThreadFunc<void*> run = () => {

                try {

                    string[] feeds = parser.parse_feeds_from_OPML(path);
                    int i = 0;
                    foreach (string feed in feeds) {
                        i++;
                        import_status_changed(i, feeds.length, feed);
                        bool temp_status = add_podcast_from_file(feed);
                        if(temp_status == false)
                            successful = false;
                    }

                } catch (Error e) {
                    info("Error parsing OPML file.");
                    info(e.message);
                    successful = false;

                }


                Idle.add((owned) callback);
                return null;
            };
            Thread.create<void*>(run, false);

            yield;

            return successful;
        }

        public bool add_podcast(Podcast podcast) throws VocalLibraryError {
            // Set all but the most recent episode as played on initial add to library
            if(podcast.episode_count() > 0) {
                for(int i = 0; i < podcast.episodes.size-1; i++) {
                    podcast.episodes[i].status = EpisodeStatus.PLAYED;
                }
            }

            string podcast_path = local_library_path + "/%s".printf(podcast.name.replace("%27", "'").replace("%", "_"));
            // Create a directory for downloads and artwork caching in the local library
            GLib.DirUtils.create_with_parents(podcast_path, 0775);

            //  Locally cache the album art if necessary
            try {
                // Don't use the default coverart_path getter, we want to make sure we are using the remote URI
                GLib.File remote_art = GLib.File.new_for_uri(podcast.remote_art_uri);

                // Set the path of the new file and create another object for the local file
                string art_path = podcast_path + "/" + remote_art.get_basename().replace("%", "_");
                GLib.File local_art = GLib.File.new_for_path(art_path);

                // If the local album art doesn't exist
                if(!local_art.query_exists()) {

                    // Cache the art
                    remote_art.copy(local_art, FileCopyFlags.NONE);

                    // Mark the local path on the podcast
                    podcast.local_art_uri = """file://""" + art_path;
                }

            } catch(Error e) {
                error("Unable to save a local copy of the album art.\n");
            }


            // Open the database
            int ec = Sqlite.Database.open (db_location, out db);
	        if (ec != Sqlite.OK) {
		        stderr.printf ("Can't open database: %d: %s\n", db.errcode (), db.errmsg ());
		        return false;
	        }

	        string content_type_text = podcast.content_type.to_string();
            string name, feed_uri, album_art_url, album_art_local_uri, description;

            name = podcast.name.replace("'", "%27");
            feed_uri = podcast.feed_uri.replace("'", "%27");
            album_art_url = podcast.remote_art_uri.replace("'", "%27");
            album_art_local_uri = podcast.local_art_uri.replace("'", "%27");
            description = podcast.description.replace("'", "%27");



            string query = """INSERT OR REPLACE INTO Podcast (name, feed_uri, album_art_url, album_art_local_uri, description, content_type)
                VALUES ('%s','%s','%s','%s', '%s', '%s');""".printf(name, feed_uri, album_art_url, album_art_local_uri,
                description, content_type_text);


            string errmsg;


            ec = db.exec (query, null, out errmsg);
	        if (ec != Sqlite.OK) {
		        stderr.printf ("Error: %s\n", errmsg);
		        return false;
	        }

	        // Now that the podcast is in the database, add it to the local arraylist
	        podcasts.add(podcast);


            foreach(Episode episode in podcast.episodes) {
                string title, parent_podcast_name, uri, episode_description;
                title = episode.title.replace("'", "%27");
                parent_podcast_name = podcast.name.replace("'", "%27");
                uri = episode.uri.replace("'", "%27");
                episode_description = episode.description.replace("'", "%27");

                string played_text = episode.status.to_string();
                string download_text = episode.download_status.to_string();

                query = """INSERT OR REPLACE INTO Episode (title, parent_podcast_name, uri, local_uri, description, release_date, download_status, play_status) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s');"""
                    .printf(title, parent_podcast_name, uri, episode.local_uri, episode_description, episode.date_released, download_text, played_text);


                ec = db.exec (query, null, out errmsg);
                if (ec != Sqlite.OK) {
                    stderr.printf ("Error: %s\n", errmsg);
                }
            }


	        return true;

        }

		/*
		 * Adds a new podcast to the library from a given file path by parsing the file's contents
		 */
        public bool add_podcast_from_file(string path) {

            string uri = path;

            // Discover the real URI (avoid redirects)
            if(path.contains("http")) {
                uri = Utils.get_real_uri(path);
            }
            info("Adding podcast from: %s".printf(uri));
            parser = new FeedParser();

            Podcast new_podcast = parser.get_podcast_from_file(uri);
            if(new_podcast == null) {
                return false;
            } else {
                add_podcast(new_podcast);
                return true;
            }

        }

        public async bool async_add_podcast_from_file(string path) {
            bool successful = true;

            SourceFunc callback = async_add_podcast_from_file.callback;

            ThreadFunc<void*> run = () => {

                info("Adding podcast from file: %s", path);
                parser = new FeedParser();

                try {
                    Podcast new_podcast = parser.get_podcast_from_file(path);
                    if(new_podcast == null) {
                        info("New podcast found to be null.");
                        successful = false;
                    } else {
                        add_podcast(new_podcast);
                    }
                } catch (Error e) {
                    error(e.message);
                    successful = false;
                }

                Idle.add((owned) callback);
                return null;

            };
            Thread.create<void*>(run, false);

            yield;

            return successful;
        }

        /*
         * Checks library for downloaded episodes that are played and over a week old
         */
        public async void autoclean_library() {
            SourceFunc callback = autoclean_library.callback;

            ThreadFunc<void*> run = () => {
                // Create a new DateTime that is the current date and then subtract one week
                GLib.DateTime week_ago = new GLib.DateTime.now_utc();
                week_ago.add_weeks(-1);

                foreach(Podcast p in podcasts) {
                    foreach(Episode e in p.episodes) {

                        // If e is downloaded, played, and more than a week old
                        if(e.download_status == DownloadStatus.DOWNLOADED &&
                            e.status == EpisodeStatus.PLAYED && e.datetime_released.compare(week_ago) == -1) {

                            // Delete the episode. Skip checking for an existing file, the delete_episode method will do that automatically
                            info("Episode %s is more than a week old. Deleting.".printf(e.title));
                            delete_local_episode(e);
                        }
                    }
                }

                Idle.add((owned) callback);
                return null;

            };
            Thread.create<void*>(run, false);

            yield;
        }

        /*
         * Checks to see if the local database file exists
         */
        public bool check_database_exists() {
            File file = File.new_for_path (db_location);
	        return file.query_exists ();
        }

        public async Gee.ArrayList<Episode> check_for_updates() throws Error{

            SourceFunc callback = check_for_updates.callback;
            parser = new FeedParser();
            var new_episodes = new Gee.ArrayList<Episode>();

            ThreadFunc<void*> run = () => {
                foreach(Podcast podcast in podcasts) {
                    try {

                        // FIXME: A Better way to validate URIs. See SOUP_URI_VALID_FOR_HTTP
                        if (podcast.feed_uri != null && podcast.feed_uri.length > 4) {
                            new_episodes = parser.update_feed(podcast);
                        }

                        foreach (var episode in new_episodes) {
                            write_episode_to_database(episode);
                            podcast.add_episode(episode);
                        }

                    } catch(Error e) {
                        throw e;
                    }

                }

                Idle.add((owned) callback);
                return null;
            };
            Thread.create<void*>(run, false);

            yield;

            return new_episodes;
        }

        public void delete_local_episodes(Gee.ArrayList<Episode> episodes) {
            foreach(Episode episode in episodes) {
                delete_local_episode(episode);
            }
        }

        public void delete_local_episode(Episode episode) {
            GLib.File local = GLib.File.new_for_path(episode.local_uri);
            if(local.query_exists()) {
                local.delete();
            }

            // Clear the fields in the episode
            string title = episode.title.replace("'", "%27");
            string query = """UPDATE Episode SET download_status = 'not_downloaded', local_uri = NULL WHERE title = '%s'""".printf(title);

            string errmsg;
            int ec = db.exec (query, null, out errmsg);

            if (ec != Sqlite.OK) {
                error(errmsg);
            }

            episode.download_status = DownloadStatus.NOT_DOWNLOADED;
            episode.local_uri = null;

            recount_unplayed();
        }

        /*
         * Downloads a podcast to the local directory and creates a DownloadDetailBox that is useful
         * for displaying download progress information later
         */
        public DownloadDetailBox? download_episode(Episode episode) {
            if(episode.download_status == DownloadStatus.DOWNLOADED) {
                info("Error. Episode %s is already downloaded. Will not download", episode.title);
                return null;
            }

            //  download_starting();
            
            string library_location;

            if(settings.library_location != null) {
                library_location = settings.library_location;
            } else {
                library_location = GLib.Environment.get_user_data_dir() + """/vocal""";
            }

            // Create a file object for the remotely hosted file
            GLib.File remote_file = GLib.File.new_for_uri(episode.uri);

            DownloadDetailBox detail_box = null;

            // Set the path of the new file and create another object for the local file
            try {
                string path = library_location + "/%s/%s".printf(episode.parent.name.replace("%27", "'").replace("%", "_"), remote_file.get_basename());
                GLib.File local_file = GLib.File.new_for_path(path);

                detail_box = new DownloadDetailBox(episode);
                info("starting download");
                detail_box.download_has_completed_successfully.connect(on_successful_download);
                info("after signal");
                FileProgressCallback callback = detail_box.download_delegate;
                GLib.Cancellable cancellable = new GLib.Cancellable();

                detail_box.cancel_requested.connect( () => {
                    cancellable.cancel();
                    bool exists = local_file.query_exists();
                    if(exists) {
                        try {
                            local_file.delete();
                        } catch(Error e) {
                            info("Unable to delete file.\n");
                        }
                    }

                });


                remote_file.copy_async(local_file, FileCopyFlags.OVERWRITE, Priority.DEFAULT, cancellable, callback);

                // Set the episode's local uri to the new path
                episode.local_uri = path;
                mark_episode_as_downloaded(episode);
            } catch (Error e) {
                error("Error downloading podcast %s", e.message);
            }

            if(batch_download_count > 0) {
                batch_notification_needed = true;
            }
            batch_download_count++;

            info("returning download box");
            return detail_box;
        }

        /*
         * Adds an episode to the queue
         */
        public void enqueue_episode(Episode e) {
            if(!queue.contains(e)){
                queue.add(e);
                queue_changed();
            }
        }

        /*
         * Returns the next episode to be played in the queue
         */
        public Episode? get_next_episode_in_queue() {
            if(queue.size > 0) {
                Episode temp =  queue[0];
                queue.remove(queue[0]);
                queue_changed();
                return temp;
            } else {
                return null;
            }
        }

        /*
         * Moves an episode higher up in the queue so it will be played quicker
         */
        public void move_episode_up_in_queue(Episode e) {
            int i = 0;
            bool match = false;
            while(i < queue.size) {
                match = (e == queue[i]);
                if(match && i-1 >= 0) {
                    Episode old = queue[i-1];
                    queue[i-1] = queue[i];
                    queue[i] = old;
                    queue_changed();
                    return;
                }
                i++;
            }

        }

        /*
         * Moves an episode down in the queue to give other episodes higher priority
         */
        public void move_episode_down_in_queue(Episode e) {
            int i = 0;
            bool match = false;
            while(i < queue.size) {
                match = (e == queue[i]);
                if(match && i+1 < queue.size) {
                    Episode old = queue[i+1];
                    queue[i+1] = queue[i];
                    queue[i] = old;
                    queue_changed();
                    return;
                }
                i++;
            }
        }


        /*
         * Updates the queue by moving an episode in the old position to the new position
         */
        public void update_queue(int oldPos, int newPos) {
            int i;

            if(oldPos < newPos){
                for(i = oldPos; i < newPos; i++) {
                    swap(queue, i, i+1);
                }
            } else {
                for(i = oldPos; i > newPos; i--) {
                    swap(queue, i, i-1);
                }
            }
        }

        /*
         * Used by update_queue to swap episodes in the queue.
         */
        private void swap(Gee.ArrayList<Episode> q, int a, int b) {
            Episode tmp = q[a];
            q[a] = q[b];
            q[b] = tmp;
        }


        /*
         * Removes an episode from the queue altogether
         */
        public void remove_episode_from_queue(Episode e) {
            foreach(Episode ep in queue) {
                if(e == ep) {
                    queue.remove(e);
                    queue_changed();
                    return;
                }
            }
        }


        /*
         * Exports the current podcast subscriptions to a file at the provided path
         */
        public void export_to_OPML(string path) {
            File file = File.new_for_path (path);
	        try {
	            GLib.DateTime now = new GLib.DateTime.now(new TimeZone.local());
	            string header = """<?xml version="1.0" encoding="UTF-8"?>
<opml version="1.0">
<head>
    <title>Vocal Subscriptions Export</title>
    <dateCreated>%s</dateCreated>
    <dateModified>%s</dateModified>
</head>
<body>
    """.printf(now.to_string(), now.to_string());
		        FileIOStream stream = file.create_readwrite (FileCreateFlags.REPLACE_DESTINATION);
		        stream.output_stream.write (header.data);

		        string output_line;

		        foreach(Podcast p in podcasts) {

		            output_line =
    """<outline text="%s" type="rss" xmlUrl="%s"/>
    """.printf(p.name.replace("\"", "'").replace("&", "and"), p.feed_uri);
		            stream.output_stream.write(output_line.data);
		        }

		        const string footer = """
</body>
</opml>
""";

		        stream.output_stream.write(footer.data);
	        } catch (Error e) {
		        warning ("Error: %s\n", e.message);
	        }
        }

        public async void mark_all_as_played_async(Podcast highlighted_podcast) {

            SourceFunc callback = mark_all_as_played_async.callback;

            ThreadFunc<void*> run = () => {
                mark_all_episodes_as_played(highlighted_podcast);

                Idle.add((owned) callback);
                return null;
            };
            Thread.create<void*>(run, false);

            yield;
        }

        public void mark_all_episodes_as_played(Podcast highlighted_podcast) {
            foreach(Episode episode in highlighted_podcast.episodes) {
                mark_episode_as_played(episode);
            }

            recount_unplayed();
            set_new_badge();
        }

        public void mark_episodes_as_played(Gee.ArrayList<Episode> episodes) {
            foreach (var episode in episodes) {
                mark_episode_as_played(episode);
            }
        }

        public void mark_episode_as_downloaded(Episode episode) {
            string query, errmsg;
            int ec;
            string title, uri;

            title = episode.title.replace("'", "%27");
            uri = episode.local_uri;

            query = """UPDATE Episode SET download_status = 'downloaded', local_uri = '%s' WHERE title = '%s'""".printf(uri,title);

            ec = db.exec (query, null, out errmsg);

            if (ec != Sqlite.OK) {
                error("Error: %s\n", errmsg);
            }
            
            episode.download_status = DownloadStatus.DOWNLOADED;
        }

        /*
         * Marks an episode as played in the database
         */
        public void mark_episode_as_played(Episode episode) {
            if(episode.status == EpisodeStatus.PLAYED){
                info("Episode is already played");
                return;
            }

            episode.status = EpisodeStatus.PLAYED;
            string query, errmsg;
            int ec;
            string title;
            title = episode.title.replace("'", "%27");


            query = """UPDATE Episode SET play_status = 'played' WHERE title = '%s'""".printf(title);

            ec = db.exec (query, null, out errmsg);

            if (ec != Sqlite.OK) {
                error(errmsg);
            }
        }

        public void mark_episodes_as_unplayed(Gee.ArrayList<Episode> episodes) {
            foreach (var episode in episodes) {
                mark_episode_as_unplayed(episode);
            }
        }

        public void mark_episode_as_unplayed(Episode episode) {
            if(episode.status == EpisodeStatus.UNPLAYED) {
                info("Episode already marked as unplayed");
                return;
            }
            episode.status = EpisodeStatus.UNPLAYED;

            string query, errmsg;
            int ec;
            string title;
            title = episode.title.replace("'", "%27");

            query = """UPDATE Episode SET play_status = 'unplayed' WHERE title = '%s'""".printf(title);

            ec = db.exec (query, null, out errmsg);

            if (ec != Sqlite.OK) {
                error(errmsg);
            }

            set_new_badge();
        }

        public void on_successful_download(string episode_title, string parent_podcast_name) {
            batch_download_count--;
            try {
                recount_unplayed();
                set_new_badge();

#if HAVE_LIBNOTIFY

            if(!batch_notification_needed) {
                string message = _("'%s' from '%s' has finished downloading.").printf(episode_title.replace("%27", "'"), parent_podcast_name.replace("%27","'"));
                var notification = new Notify.Notification(_("Episode Download Complete"), message, null);
                if(!controller.window.focus_visible)
                    notification.show();
            } else {
                if(batch_download_count == 0) {
                    var notification = new Notify.Notification(_("Downloads Complete"), _("New episodes have been downloaded."), "vocal");
                    batch_notification_needed = false;
                    if(!controller.window.focus_visible)
                        notification.show();
                }
            }

#endif

                // Find the episode in the library
                downloaded_episode = null;
                bool found = false;

                foreach(Podcast podcast in podcasts) {
                    if(!found) {
                        if(parent_podcast_name == podcast.name) {
                            foreach(Episode episode in podcast.episodes) {
                                if(episode_title == episode.title) {
                                    downloaded_episode = episode;
                                    found = true;
                                }
                            }

                        }
                    }
                }

                // If the episode was found (and it should have been), mark as downloaded and write to database
                if(downloaded_episode != null) {
                    mark_episode_as_downloaded(downloaded_episode);
                }

            } catch(Error e) {
                error(e.message);
            } finally {
                download_finished(downloaded_episode);
            }

        }

        /*
         * Opens the database and prepares for queries
         */
        private int prepare_database() {
            assert(db_location != null);

            // Open a database:
            int ec = Sqlite.Database.open (db_location, out db);
            if (ec != Sqlite.OK) {
	            stderr.printf ("Can't open database: %d: %s\n", db.errcode (), db.errmsg ());
	            return -1;
            }

            return 0;
        }

        public void recount_unplayed() {
            int new_episode_count = 0;
            foreach(Podcast podcast in podcasts) {
                new_episode_count += podcast.unplayed_count;
            }

            set_new_badge();
        }

        /*
         * Refills the local library from the contents stored in the database
         */
        public void refill_library() {

            podcasts.clear();
            prepare_database();

            Sqlite.Statement stmt;

	        string prepared_query_str = "SELECT * FROM Podcast ORDER BY name";
	        int ec = db.prepare_v2 (prepared_query_str, prepared_query_str.length, out stmt);
	        if (ec != Sqlite.OK) {
		        warning("%d: %s\n".printf(db.errcode (), db.errmsg ()));
		        return;
	        }

	        // Use the prepared statement:

	        int cols = stmt.column_count ();
	        while (stmt.step () == Sqlite.ROW) {

	            Podcast current = new Podcast();
		        for (int i = 0; i < cols; i++) {
			        string col_name = stmt.column_name (i) ?? "<none>";
			        string val = stmt.column_text (i) ?? "<none>";

                    if(col_name == "name") {
                        current.name = val;
                    }
                    else if(col_name == "feed_uri") {
                        current.feed_uri = val;
                    }
                    else if (col_name == "album_art_url") {
                        current.remote_art_uri = val;
                    }
                    else if (col_name == "album_art_local_uri") {
                        current.local_art_uri = val;
                    }
                    else if(col_name == "description") {
                        current.description = val;
                    }
                    else if (col_name == "content_type") {
                        current.content_type = MediaType.from_string(val);
                    }
		        }

		        podcasts.add(current);
	        }

	        stmt.reset();


	        // Repeat the process with the episodes

	        foreach(Podcast p in podcasts) {
                var all_episodes = new Gee.ArrayList<Episode>();

	            prepared_query_str = "SELECT * FROM Episode WHERE parent_podcast_name = '%s' ORDER BY rowid ASC".printf(p.name);
	            ec = db.prepare_v2 (prepared_query_str, prepared_query_str.length, out stmt);
	            if (ec != Sqlite.OK) {
		            stderr.printf ("Error: %d: %s\n", db.errcode (), db.errmsg ());
		            return;
	            }

	            cols = stmt.column_count ();
	            while (stmt.step () == Sqlite.ROW) {

	                Episode current_ep = new Episode();
	                current_ep.parent = p;
		            for (int i = 0; i < cols; i++) {
			            string col_name = stmt.column_name (i) ?? "<none>";
			            string val = stmt.column_text (i) ?? "<none>";

                        if(col_name == "title") {
                            current_ep.title = val;
                        }
                        else if(col_name == "description") {
                            current_ep.description = val;
                        }
                        else if (col_name == "uri") {
                            current_ep.uri = val;
                        }
                        else if (col_name == "local_uri") {
                            if(val != "(null)")
                                current_ep.local_uri = val;
                        }
                        else if (col_name == "release_date") {
                            current_ep.date_released = val;
                            current_ep.set_datetime_from_pubdate();
                        }
                        else if(col_name == "download_status") {
                            current_ep.download_status = DownloadStatus.from_string(val);
                            }
                        else if (col_name == "play_status") {
                            current_ep.status = EpisodeStatus.from_string(val);
                        }
                        else if (col_name == "latest_position") {
                            double position = 0;
                            if(double.try_parse(val, out position)) {
                                current_ep.last_played_position = position;
                            }
                        }
		            }

                    all_episodes.add(current_ep);
	            }

                p.add_episodes(all_episodes);

	            stmt.reset();
            }

            recount_unplayed();
            set_new_badge();
        }

        public ArrayList<Podcast> find_matching_podcasts(string term) {

            ArrayList<Podcast> matches = new ArrayList<Podcast>();

            prepare_database();

            Sqlite.Statement stmt;

            string prepared_query_str = "SELECT * FROM Podcast WHERE name LIKE ? ORDER BY name";
            int ec = db.prepare_v2 (prepared_query_str, prepared_query_str.length, out stmt);
            ec = stmt.bind_text(1, term, -1, null);
            if (ec != Sqlite.OK) {
                warning("%d: %s\n".printf(db.errcode (), db.errmsg ()));
                return matches;
            }

            // Use the prepared statement:

            int cols = stmt.column_count ();
            while (stmt.step () == Sqlite.ROW) {

                Podcast current = new Podcast();
                for (int i = 0; i < cols; i++) {
                    string col_name = stmt.column_name (i) ?? "<none>";
                    string val = stmt.column_text (i) ?? "<none>";

                    if(col_name == "name") {
                        current.name = val;
                    }
                    else if(col_name == "feed_uri") {
                        current.feed_uri = val;
                    }
                    else if (col_name == "album_art_url") {
                        current.remote_art_uri = val;
                    }
                    else if (col_name == "album_art_local_uri") {
                        current.local_art_uri = val;
                    }
                    else if(col_name == "description") {
                        current.description = val;
                    }
                    else if (col_name == "content_type") {
                        current.content_type = MediaType.from_string(val);
                    }
                }

                //Add the new podcast
                matches.add(current);

            }

            stmt.reset();
            return matches;
        }

        public ArrayList<Episode> find_matching_episodes(string term) {

            ArrayList<Episode> matches = new ArrayList<Episode>();

            prepare_database();

            Sqlite.Statement stmt;

            string prepared_query_str = "SELECT * FROM Episode WHERE title LIKE '%'||?||'%' ORDER BY title";
            int ec = db.prepare_v2 (prepared_query_str, prepared_query_str.length, out stmt);
            ec = stmt.bind_text(1, term, -1, null);
            if (ec != Sqlite.OK) {
                warning("%d: %s\n".printf(db.errcode (), db.errmsg ()));
                return matches;
            }

            // Use the prepared statement:

            int cols = stmt.column_count ();
            while (stmt.step () == Sqlite.ROW) {

                Episode current_ep = new Episode();
                current_ep.parent = new Podcast();

                for (int i = 0; i < cols; i++) {
                    string col_name = stmt.column_name (i) ?? "<none>";
                    string val = stmt.column_text (i) ?? "<none>";

                    if(col_name == "title") {
                        current_ep.title = val;
                    }
                    else if(col_name == "description") {
                        current_ep.description = val;
                    }
                    else if (col_name == "uri") {
                        current_ep.uri = val;
                    }
                    else if (col_name == "local_uri") {
                        if(val != "(null)")
                            current_ep.local_uri = val;
                    }
                    else if (col_name == "release_date") {
                        current_ep.date_released = val;
                        current_ep.set_datetime_from_pubdate();
                    }
                    else if(col_name == "download_status") {
                        current_ep.download_status = DownloadStatus.from_string(val);
                    }
                    else if (col_name == "play_status") {
                        current_ep.status = EpisodeStatus.from_string(val);
                    }
                    else if (col_name == "latest_position") {
                        double position = 0;
                        if(double.try_parse(val, out position)) {
                            current_ep.last_played_position = position;
                        }
                    }
                    else if(col_name == "parent_podcast_name") {
                        current_ep.parent.name = val;
                    }
                }

                //Add the new episode
                matches.add(current_ep);
            }

            stmt.reset();
            return matches;
        }

        public void unsubscribe_from_podcast(Podcast podcast) {
            // Delete the podcast's episodes from the database
            string query = "DELETE FROM Episode WHERE parent_podcast_name = '%s';".printf(podcast.name.replace("'", "%27"));

            string errmsg;
            int ec = db.exec (query, null, out errmsg);
	        if (ec != Sqlite.OK) {
		        stderr.printf ("Error: %d: %s\n", db.errcode (), db.errmsg ());
		        return;
	        }

            query = "DELETE FROM Podcast WHERE name = '%s';".printf(podcast.name.replace("'", "%27"));
            ec = db.exec (query, null, out errmsg);

            if (ec != Sqlite.OK) {
                stderr.printf ("Error: %s\n", errmsg);
            }

            // Remove the local object as well
            podcasts.remove(podcast);
            
            on_unsubscribed_from_podcast();
        }

        public Gee.ArrayList<Podcast>? search_by_term(string term) {

            prepare_database();

            Sqlite.Statement stmt;

            Gee.ArrayList<Podcast> search_pods = new Gee.ArrayList<Podcast>();

            string prepared_query_str = "SELECT * FROM Podcast WHERE name='%s' ORDER BY name".printf(term);
            int ec = db.prepare_v2 (prepared_query_str, prepared_query_str.length, out stmt);
            if (ec != Sqlite.OK) {
                warning("%d: %s\n".printf(db.errcode (), db.errmsg ()));
                return null;
            }

            // Use the prepared statement:

            int cols = stmt.column_count ();

            while (stmt.step () == Sqlite.ROW) {

                Podcast current = new Podcast();

                for (int i = 0; i < cols; i++) {
                    string col_name = stmt.column_name (i) ?? "<none>";
                    string val = stmt.column_text (i) ?? "<none>";

                    if(col_name == "name") {
                        current.name = val;
                    }
                    else if(col_name == "feed_uri") {
                        current.feed_uri = val;
                    }
                    else if (col_name == "album_art_url") {
                        current.remote_art_uri = val;
                    }
                    else if (col_name == "album_art_local_uri") {
                        current.local_art_uri = val;
                    }
                    else if(col_name == "description") {
                        current.description = val;
                    }
                    else if (col_name == "content_type") {
                        current.content_type = MediaType.from_string(val);
                    }
                }

                //Add the new podcast
                search_pods.add(current);

            }

            stmt.reset();

            return search_pods;

        }

        public void set_episode_playback_position(Episode episode) {
            string query, errmsg;
            int ec;
            string title = episode.title.replace("'", "%27");
            string position_text = episode.last_played_position.to_string();


            query = """UPDATE Episode SET latest_position = '%s' WHERE title = '%s'""".printf(position_text,title);

            ec = db.exec (query, null, out errmsg);

            if (ec != Sqlite.OK) {
                stderr.printf ("Error: %s\n", errmsg);
            }
        }

/*
        public void set_launcher_progress(double progress) {
#if HAVE_LIBUNITY
            if(progress > 0.0 && progress < 1.0) {
                launcher.progress = progress;
                launcher.progress_visible = true;
            }
            else {
                launcher.progress_visible = false;
            }
#endif
        }

*/
        /*
         * Sets the count on the launcher to match the number of unplayed episodes (if there are
         * unplayed episodes) if libunity is enabled.
         */
        public void set_new_badge() {
#if HAVE_LIBUNITY
            /*  launcher.count = new_episode_count;
            if(new_episode_count > 0) {
                launcher.count_visible = true;
            } else {
                launcher.count_visible = false;
            }  */
#endif
        }

        public void set_new_local_album_art(string path_to_local_file, Podcast p) {
            GLib.File current_file = GLib.File.new_for_path(path_to_local_file);

            InputStream input_stream = current_file.read();

            string path = settings.library_location + "/%s/cover.jpg".printf(p.name.replace("%27", "'").replace("%", "_"));
            GLib.File local_file = GLib.File.new_for_path(path);

            current_file.copy_async(local_file, FileCopyFlags.OVERWRITE, Priority.DEFAULT, null, null);

            // Set the new file location in the database
            string query, errmsg;
            int ec;

            query = """UPDATE Podcast SET album_art_local_uri = '%s' WHERE name = '%s'""".printf(local_file.get_uri(),p.name);

            ec = db.exec (query, null, out errmsg);
            if (ec != Sqlite.OK) {
                error("Error: %s\n", errmsg);
            }

            p.local_art_uri = local_file.get_uri();
        }

        /*
         * Creates Vocal's config directory, establishes a new SQLite database, and creates
         *  tables for both Podcasts and Episodes
         */
        public bool setup_library() {


            if(settings.library_location == null) {
                settings.library_location = GLib.Environment.get_user_data_dir() +  """/vocal""";
            }
            local_library_path = settings.library_location.replace("~", GLib.Environment.get_user_data_dir());

            // If the new local_library_path has been modified, update the setting
            if(settings.library_location != local_library_path)
            {
                settings.library_location = local_library_path;
            }

            // Create the local library
            GLib.DirUtils.create_with_parents(local_library_path, 0775);

            // Create the vocal folder if it doesn't exist
            GLib.DirUtils.create_with_parents(db_directory, 0775);


            // Create the database
            Sqlite.Database db;
            string error_message;

            int ec = Sqlite.Database.open(db_location, out db);
            if(ec != Sqlite.OK) {
                stderr.printf("Unable to create database at %s\n", db_location);
                return false;
            } else {
                string query = """
                    CREATE TABLE Podcast (
                    id                  INT,
			        name	            TEXT	PRIMARY KEY		NOT NULL,
			        feed_uri	        TEXT					NOT NULL,
			        album_art_url       TEXT,
			        album_art_local_uri TEXT,
			        description         TEXT                    NOT NULL,
			        content_type        TEXT
		            );

		            CREATE TABLE Episode (
			        title	            TEXT	PRIMARY KEY		NOT NULL,
			        parent_podcast_name TEXT                    NOT NULL,
			        parent_podcast_id   INT,
			        uri	                TEXT					NOT NULL,
			        local_uri           TEXT,
			        release_date        TEXT,
                    description         TEXT,
                    latest_position     TEXT,
                    download_status     TEXT,
                    play_status         TEXT
		            );

		            """;
	            ec = db.exec (query, null, out error_message);
	            if(ec != Sqlite.OK) {
	                stderr.printf("Unable to execute query at %s\n", db_location);
                }
                return true;
            }
        }



        /*
         * Writes a new episode to the database
         */
        public void write_episode_to_database(Episode episode) {

            string query, errmsg;
            int ec;
            string title, parent_podcast_name, uri, episode_description;
            title = episode.title.replace("'", "%27");
            parent_podcast_name = episode.parent.name.replace("'", "%27");
            uri = episode.uri;
            episode_description = episode.description.replace("'", "%27");


            string played_text = episode.status.to_string();
            string download_text = episode.download_status.to_string();

            query = """INSERT OR REPLACE INTO Episode (title, parent_podcast_name, uri, local_uri, description, release_date, download_status, play_status) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s');"""
                .printf(title, parent_podcast_name, uri, episode.local_uri, episode_description, episode.date_released, download_text, played_text);

            ec = db.exec (query, null, out errmsg);

            if (ec != Sqlite.OK) {
                error ("Error: %s\n", errmsg);
            }
        }
    }
}
