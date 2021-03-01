/*-
 * Copyright (c) 2015 Wingpanel Developers (http://launchpad.net/wingpanel)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Library General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

public class AyatanaCompatibility.MetaIndicator : Wingpanel.Indicator {
    private Gee.HashSet<string> blacklist;
    private IndicatorFactory indicator_loader;

    private Gee.LinkedList<AyatanaCompatibility.Indicator> deferred_indicators;
    private bool wingpanel_defer_register = true;
    private bool wingpanel_defer_waiting = false;

    public MetaIndicator () {
        Object (code_name: "ayatana_compatibility");

        deferred_indicators = new Gee.LinkedList<AyatanaCompatibility.Indicator>();

        load_blacklist ();
        indicator_loader = new IndicatorFactory ();

        this.visible = false;
        var indicators = indicator_loader.get_indicators ();

        foreach (var indicator in indicators) {
            load_indicator (indicator);
        }
    }

    public override Gtk.Widget get_display_widget () {
        return new Gtk.Label ("should not be shown");
    }

    private void load_indicator (IndicatorIface indicator) {
        var entries = indicator.get_entries ();

        foreach (var entry in entries) {
            create_entry (entry);
        }

        indicator.entry_added.connect (create_entry);
        indicator.entry_removed.connect (delete_entry);
    }

    private void create_entry (Indicator indicator) {
        if (blacklist.contains (indicator.name_hint ())) {
            return;
        }

        if (wingpanel_defer_register) {
            defer_create_entry (indicator);
        } else {
            Wingpanel.IndicatorManager.get_default ().register_indicator (indicator.code_name, indicator);
        }
    }

    private void defer_create_entry (Indicator deferred_indicator) {
        deferred_indicators.add (deferred_indicator);

        if (wingpanel_defer_waiting == true) {
            // We already have a timer waiting to register deferred indicators.
            return;
        }

        GLib.Timeout.add(250, () => {
            // If there are any unrealized widgets, we need to keep waiting.
            foreach (Wingpanel.Indicator indicator in Wingpanel.IndicatorManager.get_default ().get_indicators ()) {
                if (indicator.visible && indicator.get_display_widget ().get_realized () == false) return true;
            }

            // Have all indicator display widgets resize themselves later.
            // This fixes the bluetooth indicator having zero width.
            foreach (Wingpanel.Indicator indicator in Wingpanel.IndicatorManager.get_default ().get_indicators ()) {
                if (indicator.visible) indicator.get_display_widget ().queue_resize ();
            }

            // Register the deferred indicators.
            Wingpanel.IndicatorManager manager = Wingpanel.IndicatorManager.get_default ();
            foreach (Wingpanel.Indicator indicator in deferred_indicators) {
                manager.register_indicator (indicator.code_name, indicator);
            }

            deferred_indicators.clear();
            wingpanel_defer_register = false; // Any future indicators are probably safe.
            return false;
        });


    }

    private void delete_entry (Indicator indicator) {
        Wingpanel.IndicatorManager.get_default ().deregister_indicator (indicator.code_name, indicator);
    }

    public override Gtk.Widget? get_widget () {
        return new Gtk.Label ("should not be shown - wingpanel-ayatana-indicator");
    }

    public override void opened () {
    }

    public override void closed () {
    }

    private void load_blacklist () {
        blacklist = new Gee.HashSet<string> ();
        var blacklist_file = File.new_for_path ("/etc/wingpanel.d/ayatana.blacklist");
        foreach (var entry in get_restrictions_from_file (blacklist_file)) {
            blacklist.add (entry);
        }
        blacklist.add("nm-applet"); //old network indicator (duplicate)
    }

    private string[] get_restrictions_from_file (File file) {
        var restrictions = new string[] {};

        if (file.query_exists ()) {
            try {
                var dis = new DataInputStream (file.read ());
                string? line = null;

                while ((line = dis.read_line ()) != null) {
                    if (line.strip () != "") {
                        restrictions += line;
                    }
                }
            } catch (Error error) {
                warning ("Unable to load restrictions file %s: %s\n", file.get_basename (), error.message);
            }
        }

        return restrictions;
    }

}

public Wingpanel.Indicator? get_indicator (Module module, Wingpanel.IndicatorManager.ServerType server_type) {
    if (server_type != Wingpanel.IndicatorManager.ServerType.SESSION)
        return null;

    debug ("Activating AyatanaCompatibility Meta Indicator");
    var indicator = new AyatanaCompatibility.MetaIndicator ();
    return indicator;
}
