/*
    BPTransport - Budapest Public Transport
    Copyright (C) 2017  DEXTER

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Attention;

class NearbyStopsView extends Ui.View
{
  private var current_item;

  private const FONT = Gfx.FONT_SYSTEM_XTINY;

  private const LOWER_LEFT_LAT = 47.1523107;
  private const LOWER_LEFT_LON = 18.8460594;
  private const UPPER_RIGHT_LAT = 47.6837053;
  private const UPPER_RIGHT_LON = 19.3915303;

  private var location_provider;
  private var nearby_stops_data_provider;
  private var progress_lines;
  private var error_draw;
  private var location;
  private var gps_done = false;
  private var out_of_zone = false;
  private var error_response_code = null;
  private var download_done = false;
  private var nearby_stops_sent = false;

  public function initialize()
  {
    $.DEBUGGER.println("NearbyStopsView::initialize");
    current_item = 0;
    location_provider = new LocationProvider();
    nearby_stops_data_provider = new NearbyStopsDataProvider();
    progress_lines = new ProgressLines();
    error_draw = new ErrorDraw();

    View.initialize();
  }

  public function on_position(info)
  {
    location = info.position.toDegrees();
    $.DEBUGGER.println(location);
    gps_done = true;
    progress_lines.stop();

    if ($.debug)
      {
        //====== TEST_DATA ====== 
        location[0] = NearbyStopsDataProvider.LAT;
        location[1] = NearbyStopsDataProvider.LON;
      }

    if (location[0] > UPPER_RIGHT_LAT ||
        location[0] < LOWER_LEFT_LAT ||
        location[1] > UPPER_RIGHT_LON ||
        location[1] < LOWER_LEFT_LON)
      {
        out_of_zone = true;
        Ui.requestUpdate();
        return;
      }
    Ui.requestUpdate();

    nearby_stops_data_provider.get_data(location, method(:on_data));
  }

  public function on_data(response_code)
  {
    if (response_code != 200)
      {
        error_response_code = response_code;
        Ui.requestUpdate();
        return;
      }

    if (!download_done)
      {
        if (Attention has :vibrate)
          {
             var vibeData =
              [
                new Attention.VibeProfile(100, 700), // On for 0.7 second
              ];
             Attention.vibrate(vibeData);
          }
        download_done = true;
      }
    
    progress_lines.stop();

    Ui.requestUpdate();
  }

  public function on_get_nearby_stops(data)
  {
    if (data.size() == 0 ||
        data[0] != MESSAGE_TYPE_GET_NEARBY_STOPS_REPLY)
      {
        return;
      }
    data = data.slice(1, data.size());
    nearby_stops_data_provider.populate_array_from_online_data(data);
    on_data(200);
  }

  function get_language_reply()
  {
    $.DEBUGGER.println("******get_language_reply invoked");
  }
  
  public function onUpdate(dc)
  {
    //$.DEBUGGER.println(Lang.format("WAIT FOR DATA: $1$, HAS_PHONE_APP: $2$", [$.WAIT_FOR_DATA, $.HAS_PHONE_APP]));
    if (!$.WAIT_FOR_DATA)
      {
        if (!$.HAS_PHONE_APP && !location_provider.is_started())
          {
            //progress_lines.stop();
            location_provider.start(method(:on_position));
          }
        else if ($.HAS_PHONE_APP && !nearby_stops_sent)
          {
            gps_done = true;
            progress_lines.stop();
            $.COMM.send_get_nearby_stops(method(:on_get_nearby_stops));
            nearby_stops_sent = true;
          }        
      }

    dc.setPenWidth(1);

    if (handle_errors(dc))
      {
        return;
      }

    dc.setColor( Gfx.COLOR_BLACK, Gfx.COLOR_WHITE );
    dc.clear();

    var x = 5;
    var y = 0;
    var fontheight = Gfx.getFontHeight(FONT);
    var element_height = 85;

    for (var i = 0; i < 3; i++)
      {
        //$.DEBUGGER.println(i);
        var local_y = y + (i * element_height);
        if (i == 0 && current_item == 0)
          {
            dc.fillRectangle(0, 0, dc.getWidth(), element_height);
            continue;
          }
        if (current_item + i - 1 > nearby_stops_data_provider.nearby_stops_array.size() - 1)
          {
            dc.setColor( Gfx.COLOR_BLACK, Gfx.COLOR_WHITE );
            dc.fillRectangle(0, local_y - element_height + 3 * fontheight + 10, dc.getWidth(), dc.getHeight());
            continue;
          }
        var text_color;
        if (i == 1)
          {
            dc.setColor( Gfx.COLOR_DK_GRAY, Gfx.COLOR_BLACK );
            dc.fillRectangle(0, local_y - 9, dc.getWidth(), element_height);
            text_color = Gfx.COLOR_WHITE;
          }
        else
          {
            text_color = Gfx.COLOR_BLACK;
          }

        var item = nearby_stops_data_provider.nearby_stops_array[current_item + i - 1];

        dc.setColor(text_color, Gfx.COLOR_TRANSPARENT);
        if (item.get(NearbyStopsDataProvider.RESOURCE) != null)
          {
            var image = Ui.loadResource(item.get(NearbyStopsDataProvider.RESOURCE));
            dc.drawBitmap(x - 1, local_y - 5, image);
          }
        dc.drawText(x + 35, local_y - 2, FONT, item.get(NearbyStopsDataProvider.STOP), Gfx.TEXT_JUSTIFY_LEFT);
        dc.drawText(x, local_y + fontheight , FONT, item.get(NearbyStopsDataProvider.DIRECTION), Gfx.TEXT_JUSTIFY_LEFT);
        var lines_color = item.get(NearbyStopsDataProvider.COLOR);
        if (lines_color == Gfx.COLOR_BLACK)
          {
            lines_color = text_color;
          }
        dc.setColor(lines_color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, local_y + fontheight * 2 , FONT, item.get(NearbyStopsDataProvider.LINES), Gfx.TEXT_JUSTIFY_LEFT);
        dc.setColor(text_color, Gfx.COLOR_TRANSPARENT );
        var distance = Lang.format("$1$m", [Math.round(item.get(NearbyStopsDataProvider.DISTANCE)).format("%d")]);
        dc.drawText(x + dc.getWidth() - 10, local_y + fontheight * 2 , FONT, distance, Gfx.TEXT_JUSTIFY_RIGHT);
        //dc.drawLine(0, local_y + 3 * fontheight + 10, dc.getWidth(), local_y + 3 * fontheight + 10);
      }
}

  private function handle_errors(dc)
  {
    dc.setColor( Gfx.COLOR_WHITE, Gfx.COLOR_BLACK );
    dc.clear();

    if ($.WAIT_FOR_DATA)
      {
        progress_lines.draw(dc, Gfx.COLOR_BLUE, Gfx.COLOR_BLACK, 8);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        $.WRITER.writeLines(dc, "Checking for companion app...", Gfx.FONT_SYSTEM_TINY, dc.getHeight() / 2 - Gfx.getFontHeight(Gfx.FONT_SYSTEM_TINY));
        return true;
      }
    else if (out_of_zone)
      {
        error_draw.draw(dc, "Out of service zone. Maybe try travelling to Budapest first :)", 50);
        location_provider.stop();
        progress_lines.stop();
        return true;
      }
    else if (error_response_code != null)
      {
        error_draw.draw(dc, Lang.format("Error downloading data; $1$", [Utils.get_text_for_error_code(error_response_code)]), 50);
        location_provider.stop();
        progress_lines.stop();
        return true;
      }
    else if (!gps_done)
      {
        progress_lines.draw(dc, Gfx.COLOR_RED, Gfx.COLOR_BLACK, 8);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        $.WRITER.writeLines(dc, "Acquiring GPS Signal...", Gfx.FONT_SYSTEM_TINY, dc.getHeight() / 2 - Gfx.getFontHeight(Gfx.FONT_SYSTEM_TINY));
        return true;
      }
    else if (!download_done)
      {
        progress_lines.draw(dc, Gfx.COLOR_BLUE, Gfx.COLOR_BLACK, 8);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        $.WRITER.writeLines(dc, "Downloading RealTime data...", Gfx.FONT_SYSTEM_TINY, dc.getHeight() / 2 - Gfx.getFontHeight(Gfx.FONT_SYSTEM_TINY));
        return true;
      }
    else if (nearby_stops_data_provider.nearby_stops_array.size() == 0)
      {
        error_draw.draw(dc, "There are no nearby stops. Try increasing the search radius.", 50);
        location_provider.stop();
        progress_lines.stop();
        return true;
      }
    return false;
  }

  public function onShow()
  {
    nearby_stops_sent = false;
    if (!$.WAIT_FOR_DATA && !$.HAS_PHONE_APP && !location_provider.is_started())
      {
        location_provider.start(method(:on_position));
      }
  }

  public function onHide()
  {
    location_provider.stop();
    progress_lines.stop();
    nearby_stops_data_provider.clear_callback();
  }

  public function next()
  {
    if (current_item >= nearby_stops_data_provider.nearby_stops_array.size() - 1)
      {
        return true;
      }

    current_item++;
    Ui.requestUpdate();

    return true;
  }

  public function prev()
  {
    if (current_item == 0)
      {
        return true;
      }

    current_item = current_item -1;
    Ui.requestUpdate();

    return true;
  }

  public function select()
  {
    if (nearby_stops_data_provider.nearby_stops_array.size() == 0)
      {
        return false;
      }
    var nearby_stops_details_view = new NearbyStopsDetailsView(nearby_stops_data_provider.nearby_stops_array[current_item].get(NearbyStopsDataProvider.STOP_ID),
                                                             nearby_stops_data_provider.nearby_stops_array[current_item].get(NearbyStopsDataProvider.COLOR), current_item);

    nearby_stops_data_provider.clear_callback();
    Ui.pushView(nearby_stops_details_view, new BPTInputDelegate(nearby_stops_details_view), Ui.SLIDE_LEFT);

    return true;
  }

  public function back()
  {
    //System.exit();
    if (nearby_stops_sent)
      {
        $.COMM.send_exit();
      }
    if (location_provider.is_started())
      {
        location_provider.stop();
      }
      
    return false;
  }

  public function on_menu()
  {
    return true;
  }
}
