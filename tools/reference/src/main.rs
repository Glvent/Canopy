use ratatui::widgets::{
    calendar::{CalendarEventStore, Monthly},
    canvas::{Canvas, Circle, FilledLine, Line as CanvasLine, Points, Rectangle},
};
use ratatui::{
    buffer::{Buffer, Cell, CellDiffOption},
    layout::{Constraint, Direction, Flex, Layout, Margin, Rect, Spacing},
    style::{Color, Modifier, Style},
    symbols::Marker,
    text::{Line as TextLine, Span, Text},
    widgets::{
        Axis, Bar, BarChart, BarGroup, Block, BorderType, Chart, Clear, Dataset, Fill, Gauge,
        GraphType, LineGauge, List, ListItem, ListState, Paragraph, RatatuiLogo, RatatuiMascot,
        Row, Scrollbar, ScrollbarOrientation, ScrollbarState, Sparkline, StatefulWidget, Table,
        TableState, Tabs, Widget, Wrap,
    },
};
use serde_json::{Value, json};
use std::{
    env, fs,
    io::{self, Read},
    path::PathBuf,
};
use unicode_segmentation::UnicodeSegmentation;
use unicode_width::UnicodeWidthStr;

mod basic_matrix;

const SCHEMA_VERSION: u64 = 1;

fn rect(r: Rect) -> Value {
    json!({"x":r.x,"y":r.y,"width":r.width,"height":r.height})
}

fn color(c: Color) -> Value {
    match c {
        Color::Reset => json!({"kind":"named","name":"reset"}),
        Color::Black => json!({"kind":"named","name":"black"}),
        Color::Red => json!({"kind":"named","name":"red"}),
        Color::Green => json!({"kind":"named","name":"green"}),
        Color::Yellow => json!({"kind":"named","name":"yellow"}),
        Color::Blue => json!({"kind":"named","name":"blue"}),
        Color::Magenta => json!({"kind":"named","name":"magenta"}),
        Color::Cyan => json!({"kind":"named","name":"cyan"}),
        Color::Gray => json!({"kind":"named","name":"gray"}),
        Color::DarkGray => json!({"kind":"named","name":"darkGray"}),
        Color::LightRed => json!({"kind":"named","name":"lightRed"}),
        Color::LightGreen => json!({"kind":"named","name":"lightGreen"}),
        Color::LightYellow => json!({"kind":"named","name":"lightYellow"}),
        Color::LightBlue => json!({"kind":"named","name":"lightBlue"}),
        Color::LightMagenta => json!({"kind":"named","name":"lightMagenta"}),
        Color::LightCyan => json!({"kind":"named","name":"lightCyan"}),
        Color::White => json!({"kind":"named","name":"white"}),
        Color::Indexed(index) => json!({"kind":"indexed","index":index}),
        Color::Rgb(r, g, b) => json!({"kind":"rgb","r":r,"g":g,"b":b}),
    }
}

fn modifiers(m: Modifier) -> Value {
    let all = [
        (Modifier::BOLD, "bold"),
        (Modifier::DIM, "dim"),
        (Modifier::ITALIC, "italic"),
        (Modifier::UNDERLINED, "underlined"),
        (Modifier::SLOW_BLINK, "slowBlink"),
        (Modifier::RAPID_BLINK, "rapidBlink"),
        (Modifier::REVERSED, "reversed"),
        (Modifier::HIDDEN, "hidden"),
        (Modifier::CROSSED_OUT, "crossedOut"),
    ];
    Value::Array(
        all.into_iter()
            .filter(|(flag, _)| m.contains(*flag))
            .map(|(_, name)| Value::String(name.into()))
            .collect(),
    )
}

fn style(s: Style) -> Value {
    json!({
        "fg":s.fg.map(color),"bg":s.bg.map(color),
        "underlineColor":s.underline_color.map(color),
        "addModifiers":modifiers(s.add_modifier),"subModifiers":modifiers(s.sub_modifier)
    })
}

fn cell(c: &Cell) -> Value {
    let diff_option = match c.diff_option {
        CellDiffOption::None => json!({"kind":"none"}),
        CellDiffOption::Skip => json!({"kind":"skip"}),
        CellDiffOption::AlwaysUpdate => json!({"kind":"alwaysUpdate"}),
        CellDiffOption::ForcedWidth(w) => json!({"kind":"forcedWidth","width":w.get()}),
    };
    json!({"symbol":c.symbol(),"fg":color(c.fg),"bg":color(c.bg),
        "underlineColor":color(c.underline_color),"modifiers":modifiers(c.modifier),"skip":legacy_skip(c),"diffOption":diff_option})
}

#[allow(deprecated)]
fn legacy_skip(c: &Cell) -> bool {
    c.skip
}

fn buffer(area: Rect, b: &Buffer) -> Value {
    json!({"area":rect(area),"cells":b.content.iter().map(cell).collect::<Vec<_>>(),"cursor":Value::Null,"state":Value::Null})
}

fn rendered<W: Widget>(area: Rect, widget: W) -> Value {
    let mut b = Buffer::empty(area);
    widget.render(area, &mut b);
    buffer(area, &b)
}

fn case(name: &str, kind: &str, input: Value, expected: Value) -> Value {
    json!({"name":name,"kind":kind,"input":input,"expected":expected})
}

fn root(cases: Vec<Value>) -> Value {
    json!({
      "schemaVersion":SCHEMA_VERSION,
      "generatedBy":{"crate":"canopy-ratatui-reference","version":"0.1.0","command":"cargo run --manifest-path tools/reference/Cargo.toml --locked -- generate"},
      "dependencies":{"ratatui":"0.30.2","ratatuiCore":"0.1.2","ratatuiWidgets":"0.3.2","kasuari":"0.4.12","unicodeSegmentation":"1.13.3","unicodeWidth":"0.2.2","unicodeVersion":"17.0.0"},
      "cases":cases
    })
}

fn geometry_cases() -> Vec<Value> {
    let a = Rect::new(3, 4, 8, 5);
    let b = Rect::new(7, 2, 9, 5);
    let m = Margin::new(2, 1);
    vec![case(
        "rect-operations",
        "geometry",
        json!({"a":rect(a),"b":rect(b),"margin":{"horizontal":2,"vertical":1}}),
        json!({
            "right":a.right(),"bottom":a.bottom(),"area":a.area(),"isEmpty":a.is_empty(),
            "containsInside":a.contains((4,5).into()),"containsEdge":a.contains((11,9).into()),
            "intersection":rect(a.intersection(b)),"union":rect(a.union(b)),"inner":rect(a.inner(m))
        }),
    )]
}

fn unicode_cases() -> Vec<Value> {
    ["ASCII","e\u{301}","界","👩‍💻","🇺🇳","👨‍👩‍👧‍👦","क्‍ष","\r\n","\0a"]
      .into_iter().enumerate().map(|(i,s)| case(&format!("unicode-{i}"),"unicode",json!({"text":s}),json!({
          "graphemes":UnicodeSegmentation::graphemes(s,true).collect::<Vec<_>>(),"width":UnicodeWidthStr::width(s)
      }))).collect()
}

fn style_cases() -> Vec<Value> {
    let base = Style::default()
        .fg(Color::Red)
        .bg(Color::Indexed(17))
        .add_modifier(Modifier::BOLD | Modifier::ITALIC);
    let overlay = Style::default()
        .fg(Color::Rgb(1, 2, 3))
        .underline_color(Color::Blue)
        .add_modifier(Modifier::UNDERLINED)
        .remove_modifier(Modifier::ITALIC);
    vec![
        case(
            "style-default",
            "style",
            json!({"operation":"default"}),
            style(Style::default()),
        ),
        case(
            "style-reset",
            "style",
            json!({"operation":"reset"}),
            style(Style::reset()),
        ),
        case(
            "style-patch",
            "style",
            json!({"base":style(base),"overlay":style(overlay)}),
            style(base.patch(overlay)),
        ),
    ]
}

fn text_cases() -> Vec<Value> {
    let plain = Text::raw("alpha\n界e\u{301}\n");
    let styled = Text::from(vec![
        TextLine::from(vec![
            Span::styled("red", Color::Red),
            Span::styled("界", Style::default().bg(Color::Blue).bold()),
        ])
        .centered(),
        TextLine::styled("tail", Style::default().fg(Color::Indexed(99))).right_aligned(),
    ])
    .style(Style::default().fg(Color::Green));
    let area = Rect::new(4, 5, 12, 3);
    vec![
        case(
            "text-newlines-unicode",
            "text",
            json!({"content":"alpha\n界é\n"}),
            json!({"width":plain.width(),"height":plain.height(),"rendered":rendered(area,plain)}),
        ),
        case(
            "text-spans-style-alignment",
            "text",
            json!({"lines":[{"alignment":"center","spans":[{"content":"red"},{"content":"界"}]},{"alignment":"right","spans":[{"content":"tail"}]}]}),
            json!({"width":styled.width(),"height":styled.height(),"rendered":rendered(area,styled)}),
        ),
    ]
}

fn buffer_cases() -> Vec<Value> {
    let area = Rect::new(2, 3, 8, 2);
    let mut b = Buffer::empty(area);
    b.set_string(2, 3, "clipped-right", Style::default().fg(Color::Red));
    b.set_string(2, 3, "A界B", Style::default().bg(Color::Blue).bold());
    b.set_stringn(
        3,
        4,
        "e\u{301}xy",
        3,
        Style::default().fg(Color::Rgb(4, 5, 6)),
    );
    let mut wide = Buffer::empty(Rect::new(0, 0, 5, 1));
    wide.set_string(0, 0, "界x", Style::default().fg(Color::Green));
    wide.set_string(0, 0, "a", Style::default().fg(Color::Yellow));
    let prev = Buffer::with_lines(["界ab"]);
    let mut next = prev.clone();
    next.set_string(0, 0, "xy", Style::default().underlined());
    let updates = prev
        .diff(&next)
        .into_iter()
        .map(|(x, y, c)| json!({"x":x,"y":y,"cell":cell(c)}))
        .collect::<Vec<_>>();
    vec![
        case(
            "buffer-clipping-style-graphemes",
            "buffer",
            json!({"area":rect(area)}),
            buffer(area, &b),
        ),
        case(
            "buffer-wide-overwrite",
            "buffer",
            json!({"area":rect(wide.area)}),
            buffer(wide.area, &wide),
        ),
        case(
            "buffer-diff-wide",
            "diff",
            json!({"previous":buffer(prev.area,&prev),"next":buffer(next.area,&next)}),
            json!({"updates":updates}),
        ),
    ]
}

fn cj(c: Constraint) -> Value {
    match c {
        Constraint::Length(v) => json!({"kind":"length","value":v}),
        Constraint::Min(v) => json!({"kind":"min","value":v}),
        Constraint::Max(v) => json!({"kind":"max","value":v}),
        Constraint::Percentage(v) => json!({"kind":"percentage","value":v}),
        Constraint::Ratio(n, d) => json!({"kind":"ratio","numerator":n,"denominator":d}),
        Constraint::Fill(v) => json!({"kind":"fill","value":v}),
    }
}

fn layout_case(
    name: &str,
    area: Rect,
    dir: Direction,
    cs: Vec<Constraint>,
    margin: (u16, u16),
    spacing: i16,
    flex: Flex,
) -> Value {
    let sp = if spacing < 0 {
        Spacing::Overlap((-spacing) as u16)
    } else {
        Spacing::Space(spacing as u16)
    };
    let layout = Layout::default()
        .direction(dir)
        .constraints(cs.clone())
        .horizontal_margin(margin.0)
        .vertical_margin(margin.1)
        .spacing(sp)
        .flex(flex);
    let (segments, spacers) = layout.split_with_spacers(area);
    case(
        name,
        "layout",
        json!({"area":rect(area),"direction":format!("{dir:?}").to_lowercase(),"constraints":cs.into_iter().map(cj).collect::<Vec<_>>(),
      "margin":{"horizontal":margin.0,"vertical":margin.1},"spacing":spacing,"flex":format!("{flex:?}")}),
        json!({"segments":segments.iter().copied().map(rect).collect::<Vec<_>>(),"spacers":spacers.iter().copied().map(rect).collect::<Vec<_>>() }),
    )
}

fn request_layout(v: &Value) -> Value {
    let a = &v["area"];
    let area = Rect::new(
        a["x"].as_u64().unwrap() as u16,
        a["y"].as_u64().unwrap() as u16,
        a["width"].as_u64().unwrap() as u16,
        a["height"].as_u64().unwrap() as u16,
    );
    let dir = match v["direction"].as_str().unwrap_or("vertical") {
        "horizontal" => Direction::Horizontal,
        _ => Direction::Vertical,
    };
    let cs = v["constraints"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| match c["kind"].as_str().unwrap() {
            "length" => Constraint::Length(c["value"].as_u64().unwrap() as u16),
            "min" => Constraint::Min(c["value"].as_u64().unwrap() as u16),
            "max" => Constraint::Max(c["value"].as_u64().unwrap() as u16),
            "percentage" => Constraint::Percentage(c["value"].as_u64().unwrap() as u16),
            "ratio" => Constraint::Ratio(
                c["numerator"].as_u64().unwrap() as u32,
                c["denominator"].as_u64().unwrap() as u32,
            ),
            "fill" => Constraint::Fill(c["value"].as_u64().unwrap() as u16),
            other => panic!("unknown constraint {other}"),
        })
        .collect::<Vec<_>>();
    let flex = match v["flex"]
        .as_str()
        .unwrap_or("Legacy")
        .to_ascii_lowercase()
        .as_str()
    {
        "start" => Flex::Start,
        "end" => Flex::End,
        "center" => Flex::Center,
        "spacebetween" => Flex::SpaceBetween,
        "spacearound" => Flex::SpaceAround,
        "spaceevenly" => Flex::SpaceEvenly,
        _ => Flex::Legacy,
    };
    let margin = (
        v["margin"]["horizontal"].as_u64().unwrap_or(0) as u16,
        v["margin"]["vertical"].as_u64().unwrap_or(0) as u16,
    );
    let spacing = v["spacing"].as_i64().unwrap_or(0) as i16;
    let generated = layout_case(
        v["name"].as_str().unwrap_or("oracle"),
        area,
        dir,
        cs,
        margin,
        spacing,
        flex,
    );
    json!({"name":v.get("name").cloned().unwrap_or(Value::Null),"expected":generated["expected"]})
}

fn oracle() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let requests = serde_json::from_str::<Value>(&input)
        .ok()
        .and_then(|v| v.as_array().cloned())
        .unwrap_or_else(|| {
            input
                .lines()
                .filter(|l| !l.trim().is_empty())
                .map(|l| serde_json::from_str(l).unwrap())
                .collect()
        });
    println!(
        "{}",
        serde_json::to_string(&requests.iter().map(request_layout).collect::<Vec<_>>()).unwrap()
    );
}

fn layout_cases() -> Vec<Value> {
    let mut out = Vec::new();
    for flex in [
        Flex::Legacy,
        Flex::Start,
        Flex::End,
        Flex::Center,
        Flex::SpaceBetween,
        Flex::SpaceAround,
        Flex::SpaceEvenly,
    ] {
        out.push(layout_case(
            &format!("flex-{flex:?}").to_lowercase(),
            Rect::new(3, 2, 23, 5),
            Direction::Horizontal,
            vec![
                Constraint::Length(4),
                Constraint::Length(3),
                Constraint::Length(5),
            ],
            (0, 0),
            0,
            flex,
        ));
    }
    let specs = [
        (
            "all-constraints",
            Rect::new(4, 6, 37, 9),
            Direction::Horizontal,
            vec![
                Constraint::Length(4),
                Constraint::Min(3),
                Constraint::Max(7),
                Constraint::Percentage(17),
                Constraint::Ratio(2, 9),
                Constraint::Fill(2),
            ],
            (1, 2),
            1,
            Flex::Legacy,
        ),
        (
            "vertical-rounding",
            Rect::new(7, 11, 8, 11),
            Direction::Vertical,
            vec![
                Constraint::Percentage(33),
                Constraint::Percentage(33),
                Constraint::Percentage(34),
            ],
            (0, 0),
            0,
            Flex::Legacy,
        ),
        (
            "conflicting-lengths",
            Rect::new(0, 0, 7, 1),
            Direction::Horizontal,
            vec![
                Constraint::Length(5),
                Constraint::Length(5),
                Constraint::Length(5),
            ],
            (0, 0),
            0,
            Flex::Legacy,
        ),
        (
            "conflicting-minimums",
            Rect::new(0, 0, 4, 1),
            Direction::Horizontal,
            vec![Constraint::Min(3), Constraint::Min(3)],
            (0, 0),
            0,
            Flex::Start,
        ),
        (
            "overlap",
            Rect::new(2, 4, 12, 3),
            Direction::Horizontal,
            vec![
                Constraint::Length(5),
                Constraint::Length(5),
                Constraint::Length(5),
            ],
            (0, 0),
            -2,
            Flex::Start,
        ),
        (
            "spacing",
            Rect::new(2, 4, 17, 3),
            Direction::Horizontal,
            vec![
                Constraint::Fill(1),
                Constraint::Fill(2),
                Constraint::Fill(1),
            ],
            (0, 0),
            2,
            Flex::Legacy,
        ),
        (
            "margin-clamped",
            Rect::new(5, 8, 3, 2),
            Direction::Horizontal,
            vec![Constraint::Fill(1), Constraint::Fill(1)],
            (4, 3),
            0,
            Flex::SpaceEvenly,
        ),
        (
            "zero-area",
            Rect::new(9, 9, 0, 0),
            Direction::Vertical,
            vec![Constraint::Length(1), Constraint::Fill(1)],
            (0, 0),
            0,
            Flex::Center,
        ),
        (
            "tiny",
            Rect::new(65530, 65530, 5, 5),
            Direction::Vertical,
            vec![
                Constraint::Max(0),
                Constraint::Fill(0),
                Constraint::Ratio(1, 0),
            ],
            (0, 0),
            1,
            Flex::SpaceAround,
        ),
        (
            "u16-edge",
            Rect::new(65530, 1, 5, 2),
            Direction::Horizontal,
            vec![Constraint::Length(65535), Constraint::Max(65535)],
            (0, 0),
            0,
            Flex::End,
        ),
        (
            "empty-constraints",
            Rect::new(1, 1, 9, 4),
            Direction::Horizontal,
            vec![],
            (0, 0),
            0,
            Flex::Legacy,
        ),
    ];
    for (n, a, d, c, m, s, f) in specs {
        out.push(layout_case(n, a, d, c, m, s, f));
    }
    out
}

fn widget_cases() -> Vec<Value> {
    let mut out = Vec::new();
    let area = Rect::new(2, 3, 24, 6);
    let block = Block::bordered()
        .title(TextLine::from(" Canopy ").centered())
        .title_bottom(TextLine::from(" bottom ").right_aligned())
        .border_type(BorderType::Double)
        .style(Style::default().bg(Color::Blue))
        .border_style(Style::default().fg(Color::Yellow));
    out.push(case(
        "block-titles-borders-style",
        "widget",
        json!({"widget":"block"}),
        rendered(area, block),
    ));
    let paragraph = Paragraph::new(vec![
        TextLine::from(vec![
            Span::styled("wide 界 ", Style::default().fg(Color::Cyan)),
            Span::raw("words wrap here"),
        ]),
        TextLine::from("second"),
    ])
    .block(Block::bordered().title("P"))
    .wrap(Wrap { trim: true })
    .scroll((0, 1))
    .centered()
    .style(Style::default().bg(Color::Indexed(17)));
    out.push(case(
        "paragraph-wrap-scroll-alignment",
        "widget",
        json!({"widget":"paragraph"}),
        rendered(area, paragraph),
    ));

    let items = vec![
        ListItem::new("zero"),
        ListItem::new(TextLine::styled("one 界", Color::Green)),
        ListItem::new("two\ncontinued"),
        ListItem::new("three"),
    ];
    let list = List::new(items)
        .block(Block::bordered())
        .highlight_symbol(">>")
        .repeat_highlight_symbol(true)
        .highlight_style(Style::default().bg(Color::Blue).bold())
        .scroll_padding(1);
    let mut list_state = ListState::default().with_selected(Some(2)).with_offset(1);
    let mut lb = Buffer::empty(area);
    StatefulWidget::render(list, area, &mut lb, &mut list_state);
    let mut le = buffer(area, &lb);
    le["state"] = json!({"offset":list_state.offset(),"selected":list_state.selected()});
    out.push(case(
        "list-state-selection-multiline",
        "widget",
        json!({"widget":"list","selected":2,"offset":1}),
        le,
    ));

    let rows = vec![
        Row::new(["r0c0", "r0c1", "r0c2"]),
        Row::new(["wide界", "styled", "tail"]).style(Color::Cyan),
        Row::new(["r2", "long value", "x"]),
        Row::new(["r3", "b", "c"]),
    ];
    let table = Table::new(
        rows,
        [
            Constraint::Length(7),
            Constraint::Fill(1),
            Constraint::Length(4),
        ],
    )
    .header(Row::new(["A", "B", "C"]).style(Style::default().bold()))
    .footer(Row::new(["F1", "F2", "F3"]))
    .block(Block::bordered())
    .column_spacing(1)
    .row_highlight_style(Style::default().bg(Color::Blue))
    .column_highlight_style(Style::default().fg(Color::Yellow))
    .cell_highlight_style(Style::default().reversed())
    .highlight_symbol("> ");
    let mut table_state = TableState::default()
        .with_selected(Some(2))
        .with_selected_column(Some(1))
        .with_offset(1);
    let mut tb = Buffer::empty(area);
    StatefulWidget::render(table, area, &mut tb, &mut table_state);
    let mut te = buffer(area, &tb);
    te["state"] = json!({"offset":table_state.offset(),"selected":table_state.selected(),"selectedColumn":table_state.selected_column()});
    out.push(case(
        "table-header-footer-state",
        "widget",
        json!({"widget":"table","selected":2,"selectedColumn":1,"offset":1}),
        te,
    ));

    let tabs = Tabs::new(["One", "界 Two", "Three"])
        .block(Block::bordered())
        .select(1)
        .divider(" • ")
        .highlight_style(Style::default().fg(Color::Yellow).bold())
        .padding("[", "]");
    out.push(case(
        "tabs-selected-unicode",
        "widget",
        json!({"widget":"tabs","selected":1}),
        rendered(area, tabs),
    ));

    let gauge = Gauge::default()
        .block(Block::bordered())
        .ratio(0.42)
        .label("42%")
        .use_unicode(true)
        .gauge_style(Style::default().fg(Color::Green).bg(Color::DarkGray).bold());
    out.push(case(
        "gauge-unicode",
        "widget",
        json!({"widget":"gauge","ratio":0.42}),
        rendered(area, gauge),
    ));
    let line_gauge = LineGauge::default()
        .block(Block::bordered())
        .ratio(0.375)
        .label("load")
        .filled_style(Style::default().fg(Color::LightGreen))
        .unfilled_style(Style::default().fg(Color::DarkGray));
    out.push(case(
        "line-gauge",
        "widget",
        json!({"widget":"lineGauge","ratio":0.375}),
        rendered(area, line_gauge),
    ));

    let group = BarGroup::default().label(TextLine::from("Q1")).bars(&[
        Bar::default()
            .value(3)
            .label(TextLine::from("A"))
            .style(Color::Red),
        Bar::default()
            .value(7)
            .label(TextLine::from("B界"))
            .style(Color::Green),
        Bar::default()
            .value(5)
            .label(TextLine::from("C"))
            .style(Color::Blue),
    ]);
    let bar = BarChart::default()
        .block(Block::bordered())
        .bar_width(3)
        .bar_gap(1)
        .group_gap(2)
        .max(8)
        .data(group)
        .value_style(Style::default().fg(Color::Yellow));
    out.push(case(
        "bar-chart-group-labels",
        "widget",
        json!({"widget":"barChart"}),
        rendered(area, bar),
    ));

    let spark = Sparkline::default()
        .block(Block::bordered())
        .data(&[0, 1, 4, 2, 8, 3, 7, 5, 9, 0])
        .max(10)
        .style(Style::default().fg(Color::Magenta));
    out.push(case(
        "sparkline-data",
        "widget",
        json!({"widget":"sparkline"}),
        rendered(area, spark),
    ));

    let sa = Rect::new(2, 3, 3, 10);
    let scrollbar = Scrollbar::new(ScrollbarOrientation::VerticalRight)
        .begin_symbol(Some("↑"))
        .end_symbol(Some("↓"))
        .track_symbol(Some("│"))
        .thumb_symbol("█");
    let mut ss = ScrollbarState::new(40)
        .position(13)
        .viewport_content_length(8);
    let mut sb = Buffer::empty(sa);
    StatefulWidget::render(scrollbar, sa, &mut sb, &mut ss);
    let mut se = buffer(sa, &sb);
    se["state"] = json!({"contentLength":40,"position":13,"viewportContentLength":8});
    out.push(case(
        "scrollbar-state",
        "widget",
        json!({"widget":"scrollbar"}),
        se,
    ));

    let fill_area = Rect::new(2, 3, 8, 2);
    out.push(case(
        "fill-symbol-style",
        "widget",
        json!({"widget":"fill"}),
        rendered(
            fill_area,
            Fill::new("界").style(Style::default().fg(Color::Rgb(9, 8, 7)).bg(Color::Black)),
        ),
    ));
    let mut cb = Buffer::empty(fill_area);
    cb.set_string(2, 3, "erase me", Color::Red);
    Clear.render(fill_area, &mut cb);
    out.push(case(
        "clear-existing",
        "widget",
        json!({"widget":"clear","pre":"erase me"}),
        buffer(fill_area, &cb),
    ));
    out.push(case(
        "ratatui-logo",
        "widget",
        json!({"widget":"ratatuiLogo"}),
        rendered(Rect::new(1, 2, 30, 6), RatatuiLogo::default()),
    ));
    out.push(case(
        "ratatui-mascot",
        "widget",
        json!({"widget":"ratatuiMascot"}),
        rendered(Rect::new(1, 2, 32, 14), RatatuiMascot::default()),
    ));

    let data1 = [(0.0, 1.0), (2.0, 4.0), (5.0, 2.0), (8.0, 7.0), (10.0, 6.0)];
    let data2 = [(0.0, 7.0), (3.0, 3.0), (6.0, 5.0), (10.0, 1.0)];
    let chart = Chart::new(vec![
        Dataset::default()
            .name("line")
            .marker(Marker::Braille)
            .graph_type(GraphType::Line)
            .style(Color::Cyan)
            .data(&data1),
        Dataset::default()
            .name("scatter")
            .marker(Marker::Dot)
            .graph_type(GraphType::Scatter)
            .style(Color::Yellow)
            .data(&data2),
    ])
    .block(Block::bordered().title("Chart"))
    .x_axis(
        Axis::default()
            .title("x")
            .bounds([0.0, 10.0])
            .labels(["0", "5", "10"]),
    )
    .y_axis(
        Axis::default()
            .title("y")
            .bounds([0.0, 8.0])
            .labels(["0", "4", "8"]),
    );
    out.push(case(
        "chart-axes-legend-datasets",
        "widget",
        json!({"widget":"chart"}),
        rendered(Rect::new(2, 3, 40, 14), chart),
    ));

    let points = [
        (-8.0, -4.0),
        (-4.0, 1.0),
        (0.0, 0.0),
        (4.0, 3.0),
        (8.0, -2.0),
    ];
    let canvas = Canvas::default()
        .block(Block::bordered().title("Canvas"))
        .marker(Marker::Braille)
        .x_bounds([-10.0, 10.0])
        .y_bounds([-5.0, 5.0])
        .background_color(Color::Black)
        .paint(|ctx| {
            ctx.draw(&Points {
                coords: &points,
                color: Color::Yellow,
            });
            ctx.draw(&CanvasLine {
                x1: -10.0,
                y1: -5.0,
                x2: 10.0,
                y2: 5.0,
                color: Color::Cyan,
            });
            ctx.draw(&FilledLine::new(-10.0, 4.0, 10.0, 4.0, 0.0, Color::Blue));
            ctx.draw(&Rectangle {
                x: -6.0,
                y: -3.0,
                width: 4.0,
                height: 2.0,
                color: Color::Red,
            });
            ctx.draw(&Circle {
                x: 5.0,
                y: 1.0,
                radius: 2.0,
                color: Color::Green,
            });
            ctx.print(0.0, 0.0, Span::styled("origin", Color::Magenta));
        });
    out.push(case(
        "canvas-shapes-layers-print",
        "widget",
        json!({"widget":"canvas","marker":"braille"}),
        rendered(Rect::new(2, 3, 32, 12), canvas),
    ));

    let date = time::Date::from_calendar_date(2024, time::Month::February, 1).unwrap();
    let mut events = CalendarEventStore::default();
    events.add(
        time::Date::from_calendar_date(2024, time::Month::February, 14).unwrap(),
        Style::default().fg(Color::Red).bold(),
    );
    events.add(
        time::Date::from_calendar_date(2024, time::Month::February, 29).unwrap(),
        Style::default().bg(Color::Blue),
    );
    let calendar = Monthly::new(date, events)
        .show_month_header(Style::default().fg(Color::Yellow).bold())
        .show_weekdays_header(Color::Cyan)
        .show_surrounding(Color::DarkGray)
        .default_style(Color::White)
        .block(Block::bordered());
    out.push(case("monthly-calendar-leap-events","widget",json!({"widget":"monthlyCalendar","date":"2024-02-01","events":["2024-02-14","2024-02-29"]}),rendered(Rect::new(2,3,25,10),calendar)));
    out
}

fn write_fixture(name: &str, cases: Vec<Value>) {
    let out = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join("tests/fixtures")
        .join(name);
    fs::create_dir_all(out.parent().unwrap()).unwrap();
    fs::write(
        out,
        serde_json::to_string_pretty(&root(cases)).unwrap() + "\n",
    )
    .unwrap();
}

fn generate() {
    write_fixture("geometry.json", geometry_cases());
    write_fixture("style.json", style_cases());
    write_fixture("text.json", text_cases());
    write_fixture("unicode.json", unicode_cases());
    write_fixture("buffer.json", buffer_cases());
    write_fixture("layout.json", layout_cases());
    write_fixture("widgets.json", widget_cases());
}

fn main() {
    match env::args().nth(1).as_deref() {
        Some("generate") => generate(),
        Some("layout-oracle") => oracle(),
        Some("widgets-matrix") => basic_matrix::generate_matrix(),
        _ => eprintln!(
            "usage: cargo run --manifest-path tools/reference/Cargo.toml --locked -- generate|layout-oracle|widgets-matrix"
        ),
    }
}
