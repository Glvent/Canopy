use ratatui_core::{
    backend::{Backend, TestBackend},
    buffer::{Buffer, Cell, CellDiffOption},
    layout::{Position, Rect},
    style::{Color, Modifier, Style},
    terminal::{Terminal, TerminalOptions, Viewport},
};
use serde_json::{json, Value};
use std::{env, fs};

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
        Color::Indexed(i) => json!({"kind":"indexed","index":i}),
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
            .filter(|(f, _)| m.contains(*f))
            .map(|(_, n)| json!(n))
            .collect(),
    )
}

#[allow(deprecated)]
fn cell(c: &Cell) -> Value {
    let diff = match c.diff_option {
        CellDiffOption::None => json!({"kind":"none"}),
        CellDiffOption::Skip => json!({"kind":"skip"}),
        CellDiffOption::AlwaysUpdate => json!({"kind":"alwaysUpdate"}),
        CellDiffOption::ForcedWidth(w) => json!({"kind":"forcedWidth","width":w.get()}),
    };
    json!({"symbol":c.symbol(),"fg":color(c.fg),"bg":color(c.bg),
        "underlineColor":color(c.underline_color),"modifiers":modifiers(c.modifier),
        "skip":c.skip,"diffOption":diff})
}

fn rect(r: Rect) -> Value {
    json!({"x":r.x,"y":r.y,"width":r.width,"height":r.height})
}
fn buffer(b: &Buffer) -> Value {
    json!({"area":rect(b.area),"cells":b.content.iter().map(cell).collect::<Vec<_>>()})
}

fn fill_cell(c: &mut Cell, tag: u16, x: usize, y: usize) {
    let ch = char::from(b'A' + ((tag as usize + x + y * 7) % 26) as u8);
    let mut mods = Modifier::empty();
    if (tag as usize + x + y) % 3 == 0 {
        mods |= Modifier::BOLD;
    }
    if (tag as usize + x + y) % 5 == 0 {
        mods |= Modifier::ITALIC;
    }
    c.set_symbol(&ch.to_string()).set_style(
        Style::default()
            .fg(Color::Indexed(((tag as usize + x + y) % 32) as u8))
            .bg(Color::Indexed(((tag as usize * 3 + y) % 16) as u8))
            .underline_color(Color::Indexed(((tag as usize + x * 2) % 16) as u8))
            .add_modifier(mods),
    );
}

fn fill(b: &mut Buffer, tag: u16) {
    let width = b.area.width as usize;
    for (i, c) in b.content.iter_mut().enumerate() {
        let x = i % width.max(1);
        let y = i / width.max(1);
        fill_cell(c, tag, x, y);
    }
}

fn completed(completed_buffer: &Buffer, area: Rect, count: usize) -> Value {
    json!({"buffer":buffer(completed_buffer),"area":rect(area),"count":count})
}

fn snapshot(terminal: &mut Terminal<TestBackend>, completed_frame: Option<Value>) -> Value {
    let mut frame = terminal.get_frame();
    let area = frame.area();
    let count = frame.count();
    let current = frame.buffer_mut().clone();
    let backend = terminal.backend();
    let mut value = json!({"viewportArea":rect(area),"frameCount":count,"current":buffer(&current),
        "backend":{"buffer":buffer(backend.buffer()),"scrollback":buffer(backend.scrollback()),
        "cursor":{"x":backend.cursor_position().x,"y":backend.cursor_position().y},
        "cursorVisible":backend.cursor_visible()}});
    if let Some(completed_frame) = completed_frame {
        value["completedFrame"] = completed_frame;
    }
    value
}

fn run(input: &Value) -> Value {
    let width = input["screen"]["width"].as_u64().unwrap() as u16;
    let height = input["screen"]["height"].as_u64().unwrap() as u16;
    let tag = input["initialTag"].as_u64().unwrap() as u16;
    let mut backend = TestBackend::new(width, height);
    let mut initial = Buffer::empty(Rect::new(0, 0, width, height));
    fill(&mut initial, tag);
    backend
        .draw(initial.content.iter().enumerate().map(|(i, c)| {
            (
                (i % width.max(1) as usize) as u16,
                (i / width.max(1) as usize) as u16,
                c,
            )
        }))
        .unwrap();
    backend
        .set_cursor_position(Position::new(
            input["cursor"]["x"].as_u64().unwrap() as u16,
            input["cursor"]["y"].as_u64().unwrap() as u16,
        ))
        .unwrap();
    let viewport = match input["viewport"]["kind"].as_str().unwrap() {
        "fullscreen" => Viewport::Fullscreen,
        "fixed" => Viewport::Fixed(Rect::new(
            input["viewport"]["x"].as_u64().unwrap() as u16,
            input["viewport"]["y"].as_u64().unwrap() as u16,
            input["viewport"]["width"].as_u64().unwrap() as u16,
            input["viewport"]["height"].as_u64().unwrap() as u16,
        )),
        "inline" => Viewport::Inline(input["viewport"]["height"].as_u64().unwrap() as u16),
        other => panic!("unknown viewport {other}"),
    };
    let mut terminal = Terminal::with_options(backend, TerminalOptions { viewport }).unwrap();
    let mut snapshots = vec![snapshot(&mut terminal, None)];
    for action in input["actions"].as_array().unwrap() {
        let completed_frame = match action["kind"].as_str().unwrap() {
            "draw" => {
                let tag = action["tag"].as_u64().unwrap() as u16;
                let cursor = action.get("cursor").cloned().unwrap_or(Value::Null);
                let frame = terminal
                    .draw(|frame| {
                        fill(frame.buffer_mut(), tag);
                        if !cursor.is_null() {
                            frame.set_cursor_position(Position::new(
                                cursor["x"].as_u64().unwrap() as u16,
                                cursor["y"].as_u64().unwrap() as u16,
                            ));
                        }
                    })
                    .unwrap();
                Some(completed(frame.buffer, frame.area, frame.count))
            }
            "partialDraw" => {
                let tag = action["tag"].as_u64().unwrap() as u16;
                let frame = terminal
                    .draw(|frame| {
                        let area = frame.area();
                        if !area.is_empty() {
                            fill_cell(&mut frame.buffer_mut()[(area.x, area.y)], tag, 0, 0);
                        }
                    })
                    .unwrap();
                Some(completed(frame.buffer, frame.area, frame.count))
            }
            "noopDraw" => {
                let frame = terminal.draw(|_| {}).unwrap();
                Some(completed(frame.buffer, frame.area, frame.count))
            }
            "manual" => {
                fill(
                    terminal.current_buffer_mut(),
                    action["tag"].as_u64().unwrap() as u16,
                );
                terminal.flush().unwrap();
                terminal.backend_mut().flush().unwrap();
                terminal.swap_buffers();
                None
            }
            "insertBefore" => {
                let tag = action["tag"].as_u64().unwrap() as u16;
                terminal
                    .insert_before(action["height"].as_u64().unwrap() as u16, |b| fill(b, tag))
                    .unwrap();
                None
            }
            "resize" => {
                let w = action["width"].as_u64().unwrap() as u16;
                let h = action["height"].as_u64().unwrap() as u16;
                terminal.backend_mut().resize(w, h);
                terminal.resize(Rect::new(0, 0, w, h)).unwrap();
                None
            }
            "clear" => {
                terminal.clear().unwrap();
                None
            }
            other => panic!("unknown action {other}"),
        };
        snapshots.push(snapshot(&mut terminal, completed_frame));
    }
    Value::Array(snapshots)
}

fn make_case(name: String, input: Value) -> Value {
    let expected = run(&input);
    json!({"name":name,"kind":"terminal","input":input,"expected":expected})
}

fn cases() -> Vec<Value> {
    let mut out = Vec::new();
    for i in 0..36u16 {
        let w = [3u16, 5, 8][i as usize % 3];
        let h = [2u16, 4, 7][i as usize / 3 % 3];
        let kind = if i % 2 == 0 { "fullscreen" } else { "fixed" };
        let viewport = if kind == "fixed" {
            json!({"kind":kind,"x":1.min(w-1),"y":1.min(h-1),"width":w.saturating_sub(1),"height":h.saturating_sub(1)})
        } else {
            json!({"kind":kind})
        };
        let mut actions = vec![
            json!({"kind":"draw","tag":i+1,"cursor":{"x":(i+1)%w,"y":(i+1)%h}}),
            json!({"kind":"manual","tag":i+40}),
        ];
        if i % 3 == 0 {
            actions.push(json!({"kind":"resize","width":w+1,"height":h+1}));
        }
        if i % 4 == 0 {
            actions.push(json!({"kind":"clear"}));
        }
        out.push(make_case(format!("{kind}-{i:03}"), json!({"screen":{"width":w,"height":h},"cursor":{"x":i%w,"y":i%h},"cursorVisible":false,"initialTag":i,"viewport":viewport,"actions":actions})));
    }
    for i in 0..144u16 {
        let w = [3u16, 5, 8][i as usize % 3];
        let h = [2u16, 4, 7][i as usize / 3 % 3];
        let cursor_y = [0, h / 2, h - 1][i as usize / 9 % 3];
        let vh = [0, 1, h / 2, h, h + 3][i as usize / 27 % 5];
        let inserted = [0, 1, 2, h, h + 2][i as usize % 5];
        let mut actions = vec![
            json!({"kind":"draw","tag":i+3}),
            json!({"kind":"insertBefore","height":inserted,"tag":i+70}),
        ];
        if i % 4 == 0 {
            actions.push(json!({"kind":"resize","width":w+(i%3),"height":h+1}));
        }
        if i % 5 == 0 {
            actions.push(json!({"kind":"draw","tag":i+120,"cursor":{"x":i%w,"y":cursor_y}}));
        }
        if i % 11 == 0 && vh > 0 {
            actions.push(json!({"kind":"clear"}));
        }
        out.push(make_case(format!("inline-{i:03}"), json!({"screen":{"width":w,"height":h},"cursor":{"x":i%w,"y":cursor_y},"cursorVisible":false,"initialTag":i+10,"viewport":{"kind":"inline","height":vh},"actions":actions})));
    }
    for i in 0..24u16 {
        let w = [3u16, 5, 8][i as usize % 3];
        let h = [2u16, 4, 7][i as usize / 3 % 3];
        let mode = i % 3;
        let viewport = match mode {
            0 => json!({"kind":"fullscreen"}),
            1 => {
                json!({"kind":"fixed","x":1.min(w-1),"y":1.min(h-1),"width":w.saturating_sub(1),"height":h.saturating_sub(1)})
            }
            _ => json!({"kind":"inline","height":if i % 2 == 0 { h } else { 0 }}),
        };
        let first = if i % 2 == 0 {
            json!({"kind":"noopDraw"})
        } else {
            json!({"kind":"partialDraw","tag":i+180})
        };
        let actions = vec![
            first,
            json!({"kind":"partialDraw","tag":i+210}),
            json!({"kind":"insertBefore","height":0,"tag":i+230}),
        ];
        out.push(make_case(format!("partial-{i:03}"), json!({"screen":{"width":w,"height":h},"cursor":{"x":i%w,"y":i%h},"cursorVisible":false,"initialTag":i+160,"viewport":viewport,"actions":actions})));
    }
    out
}

fn main() {
    let output = env::args()
        .nth(1)
        .unwrap_or_else(|| "tests/fixtures/terminal.json".into());
    let root = json!({"schemaVersion":1,"oracle":{"crate":"ratatui-core","version":"0.1.2","ratatuiVersion":"0.30.2","features":["scrolling-regions","underline-color"]},"cases":cases()});
    fs::write(output, serde_json::to_string(&root).unwrap() + "\n").unwrap();
}
