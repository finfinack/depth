import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;
import DepthCore;

(:glance)
class depthGlanceView extends WatchUi.GlanceView
{
    private var _model as DepthModel;

    // Loaded once rather than in onUpdate(), which runs on every redraw.
    private var _depthLabel as String;
    private var _maxDepthLabel as String;

    function initialize() {
        GlanceView.initialize();

        // The glance shares the app's property store but not its lifetime: this
        // model is built and discarded on every draw, so it must leave the
        // re-zero trigger for the app's own long-lived one.
        _model = new DepthModel(DepthCore.REZERO_IGNORE);
        _depthLabel = WatchUi.loadResource(Rez.Strings.GlanceDepth) as String;
        _maxDepthLabel = WatchUi.loadResource(Rez.Strings.GlanceMaxDepth) as String;
    }

    function onUpdate(dc as Dc) as Void {
        _model.update(Activity.getActivityInfo());

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

    function onStop() as Void {
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
