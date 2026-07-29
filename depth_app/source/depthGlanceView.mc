import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;
import DepthCore;

(:glance)
class depthGlanceView extends WatchUi.GlanceView
{
    private var _model as DepthModel;
    private var _dataTimer as Timer.Timer?;

    // Loaded once rather than in onUpdate(), which runs on every redraw.
    private var _depthLabel as String;
    private var _maxDepthLabel as String;

    function initialize() {
        GlanceView.initialize();

        // The glance shares the app's property store but not its lifetime, so it
        // must leave the re-zero trigger for the app's own model to consume.
        //
        // How long this model lives depends on the device. Where there is memory
        // to spare the glance is kept alive and it accumulates across updates —
        // which is what makes a session maximum mean anything here. Where there
        // is not, the app is restarted for each update and this is built afresh
        // every time; see onShow() for what that costs.
        _model = new DepthModel(DepthCore.REZERO_IGNORE);
        _depthLabel = WatchUi.loadResource(Rez.Strings.GlanceDepth) as String;
        _maxDepthLabel = WatchUi.loadResource(Rez.Strings.GlanceMaxDepth) as String;
    }

    //! Drive the reading from a timer, exactly as the app's own view does.
    //!
    //! A glance is redrawn only when the system decides to, and that is not
    //! often enough to track anything: without this the first draw sets the
    //! baseline from the sample it is measuring, reads 0.00, and nothing ever
    //! asks for a second draw. requestUpdate() is the documented way to get a
    //! live glance on devices with the memory to keep one alive.
    //!
    //! On devices without it the call is documented to do nothing. The timer
    //! then costs one wakeup a second for as long as the glance is on screen
    //! and the reading stays where it was, which is no worse than before.
    function onShow() as Void {
        _model.update(Activity.getActivityInfo());

        // The pressure sensor updates about once per second, so polling faster
        // only costs battery. Garmin asks that glances stay at or under 1 Hz so
        // scrolling the list stays smooth, which is the same rate.
        if (_dataTimer == null) {
            _dataTimer = new Timer.Timer();
            _dataTimer.start(method(:updateDepth), 1000, true);
        }

        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        if (_dataTimer != null) {
            _dataTimer.stop();
            _dataTimer = null;
        }
    }

    //! On a timer interval, read the pressure sensor and update the depth.
    //! Sampling lives here rather than in onUpdate() so that a redraw the
    //! system asks for on its own does not feed the model a second sample in
    //! the same tick.
    function updateDepth() as Void {
        _model.update(Activity.getActivityInfo());
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var font = Graphics.FONT_GLANCE;
        var height = dc.getHeight();

        // Both values start at the same x so the two lines line up. The column
        // clears the wider of the two labels with a single space of air.
        var labelX = 0;
        var valueX = dc.getTextWidthInPixels(_maxDepthLabel + " ", font);

        // Set the two rows one line apart and centre the pair. Putting them on
        // the quarter points instead spreads them to the edges of the glance and
        // leaves a hole between them.
        var lineHeight = dc.getFontHeight(font);
        var centerY = height / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        drawRow(dc, font, labelX, valueX, centerY - lineHeight / 2, _depthLabel,
            Graphics.COLOR_BLUE, _model.depth, _model.saturated);
        drawRow(dc, font, labelX, valueX, centerY + lineHeight / 2, _maxDepthLabel,
            Graphics.COLOR_ORANGE, _model.max_depth, _model.saturation_seen);
    }

    //! One "<label>  <value><unit>" line, the label in the page accent colour
    //! and the value coloured by depth.
    private function drawRow(dc as Dc, font as Graphics.FontType, labelX as Number, valueX as Number,
                             y as Number, label as String, accent as Graphics.ColorType,
                             value as Float?, limited as Boolean) as Void {
        var justify = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(labelX, y, font, label, justify);

        var text = _model.formatBounded(value, limited);
        if (value != null) {
            text += _model.unitLabel();
        }
        text += _model.staleMark(value);
        dc.setColor(DepthCore.readingColor(value, _model.color_profile, limited),
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(valueX, y, font, text, justify);
    }
}
