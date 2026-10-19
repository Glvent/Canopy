use super::*;

pub fn generate_matrix() {
    let mut cases = Vec::new();
    for widget in [
        "gauge",
        "lineGauge",
        "tabs",
        "barChart",
        "sparkline",
        "scrollbar",
        "calendar",
        "logo",
        "mascot",
    ] {
        for width in [0u16, 1, 2, 3, 8, 21, 32] {
            for height in [0u16, 1, 2, 5, 9] {
                for config in 0..6 {
                    let area = Rect::new(2, 2, width, height);
                    let mut buf =
                        Buffer::filled(Rect::new(0, 0, width + 4, height + 4), Cell::new("."));
                    let input = json!({"widget":widget,"area":rect(area),"config":config});
                    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                        let base = Style::default()
                            .fg(Color::Yellow)
                            .bg(Color::Blue)
                            .add_modifier(Modifier::ITALIC);
                        let ratios = [0.0, 0.01, 0.375, 0.5, 0.99, 1.0];
                        match widget {
                            "gauge" => {
                                let mut w = Gauge::default()
                                    .ratio(ratios[config])
                                    .style(base)
                                    .gauge_style(Style::default().fg(Color::Green).bg(Color::Red));
                                if config % 2 == 1 {
                                    w = w.use_unicode(true);
                                }
                                if config >= 3 {
                                    w = w.label(Span::styled(
                                        "界é",
                                        Style::default().fg(Color::Cyan),
                                    ));
                                }
                                w.render(area, &mut buf);
                            }
                            "lineGauge" => {
                                let mut w = LineGauge::default()
                                    .ratio(ratios[config])
                                    .style(base)
                                    .filled_style(Style::default().fg(Color::Green))
                                    .unfilled_style(Style::default().fg(Color::Red));
                                if config >= 3 {
                                    w = w.label("界").filled_symbol("=").unfilled_symbol("-");
                                }
                                w.render(area, &mut buf);
                            }
                            "tabs" => {
                                let mut w = Tabs::new([
                                    TextLine::from("one"),
                                    TextLine::from("界é"),
                                    TextLine::from("three"),
                                ])
                                .style(base)
                                .select(if config == 5 { None } else { Some(config) })
                                .highlight_style(
                                    Style::default().bg(Color::Red).add_modifier(Modifier::BOLD),
                                );
                                if config % 2 == 1 {
                                    w = w.padding("[", "]").divider(" • ");
                                }
                                w.render(area, &mut buf);
                            }
                            "barChart" => {
                                let bars = vec![
                                    Bar::new(0).label("zero"),
                                    Bar::new(3)
                                        .label("界")
                                        .style(Style::default().fg(Color::Green))
                                        .text_value("hi"),
                                    Bar::new(u64::MAX - 1).label("max"),
                                ];
                                let group =
                                    BarGroup::new(bars).label(TextLine::from("group").centered());
                                let mut w = BarChart::default()
                                    .data(group)
                                    .bar_width(1 + (config % 3) as u16)
                                    .bar_gap((config % 2) as u16)
                                    .group_gap(1)
                                    .style(base)
                                    .bar_style(Style::default().fg(Color::Red))
                                    .label_style(Style::default().fg(Color::Cyan))
                                    .value_style(Style::default().fg(Color::White));
                                if config % 2 == 1 {
                                    w = w.direction(Direction::Horizontal);
                                }
                                if config >= 3 {
                                    w = w.max(5);
                                }
                                w.render(area, &mut buf);
                            }
                            "sparkline" => {
                                use ratatui::widgets::{RenderDirection, SparklineBar};
                                let data = [
                                    SparklineBar::from(Some(0)),
                                    SparklineBar::from(None),
                                    SparklineBar::from(Some(3))
                                        .style(Style::default().fg(Color::Green)),
                                    SparklineBar::from(Some(u64::MAX)),
                                    SparklineBar::from(Some(u64::MAX - 1)),
                                ];
                                let mut w = Sparkline::default()
                                    .data(data)
                                    .style(base)
                                    .absent_value_symbol("?")
                                    .absent_value_style(Style::default().fg(Color::Magenta));
                                if config % 2 == 1 {
                                    w = w.direction(RenderDirection::RightToLeft);
                                }
                                if config >= 3 {
                                    w = w.max(if config == 5 { 0 } else { 6 });
                                }
                                w.render(area, &mut buf);
                            }
                            "scrollbar" => {
                                let orientation = [
                                    ScrollbarOrientation::VerticalRight,
                                    ScrollbarOrientation::VerticalLeft,
                                    ScrollbarOrientation::HorizontalBottom,
                                    ScrollbarOrientation::HorizontalTop,
                                ][config % 4]
                                    .clone();
                                let mut w = Scrollbar::new(orientation)
                                    .style(base)
                                    .thumb_style(Style::default().fg(Color::Red));
                                if config == 4 {
                                    w = w.begin_symbol(None).end_symbol(None);
                                }
                                if config == 5 {
                                    w = w.track_symbol(None);
                                }
                                let mut state =
                                    ScrollbarState::new(if config == 0 { 0 } else { 9 })
                                        .position(config * 2)
                                        .viewport_content_length(if config % 2 == 0 {
                                            0
                                        } else {
                                            12
                                        });
                                StatefulWidget::render(w, area, &mut buf, &mut state);
                            }
                            "calendar" => {
                                let month = [
                                    time::Month::February,
                                    time::Month::January,
                                    time::Month::December,
                                    time::Month::August,
                                    time::Month::September,
                                    time::Month::June,
                                ][config];
                                let date = time::Date::from_calendar_date(2024, month, 1).unwrap();
                                let mut events = CalendarEventStore::default();
                                events.add(date, Style::default().bg(Color::Red));
                                let mut w = Monthly::new(date, events).default_style(base);
                                if config % 2 == 1 {
                                    w = w.show_surrounding(Style::default().fg(Color::DarkGray));
                                }
                                if config >= 2 {
                                    w = w.show_month_header(Style::default().fg(Color::Cyan));
                                }
                                if config >= 4 {
                                    w = w.show_weekdays_header(Style::default().fg(Color::Magenta));
                                }
                                w.render(area, &mut buf);
                            }
                            "logo" => {
                                if config % 2 == 0 {
                                    RatatuiLogo::tiny()
                                } else {
                                    RatatuiLogo::small()
                                }
                                .render(area, &mut buf);
                            }
                            "mascot" => {
                                RatatuiMascot::new()
                                    .set_eye(if config % 2 == 0 {
                                        ratatui::widgets::MascotEyeColor::Default
                                    } else {
                                        ratatui::widgets::MascotEyeColor::Red
                                    })
                                    .render(area, &mut buf);
                            }
                            _ => unreachable!(),
                        }
                    }));
                    if result.is_ok() {
                        cases.push(case(
                            &format!("{widget}-{width}x{height}-{config}"),
                            "widget",
                            input,
                            buffer(buf.area, &buf),
                        ));
                    }
                }
            }
        }
    }
    let out =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/widgets_matrix.json");
    fs::write(out, serde_json::to_string(&root(cases)).unwrap() + "\n").unwrap();
}
