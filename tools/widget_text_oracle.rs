//! Development-only matrix oracle. Compile through widget_text_generate.py.
use ratatui::{buffer::Buffer,layout::{Rect,Alignment,Constraint,Flex},style::{Style,Color,Modifier},
    text::{Text,Line,Span},widgets::{Paragraph,Wrap,List,ListItem,ListState,ListDirection,
    Table,Row,Cell,TableState,HighlightSpacing,Block,Widget,StatefulWidget}};
use serde_json::{json,Value};

fn capture(b: &Buffer) -> Value {
    json!(b.content.iter().map(|c| json!([c.symbol(),format!("{:?}",c.fg),format!("{:?}",c.bg),
        format!("{:?}",c.underline_color),c.modifier.bits()])).collect::<Vec<_>>())
}
fn alignment(i:usize)->Alignment {[Alignment::Left,Alignment::Center,Alignment::Right][i]}
fn spacing(i:usize)->HighlightSpacing {[HighlightSpacing::WhenSelected,HighlightSpacing::Always,HighlightSpacing::Never][i].clone()}
fn main() {
    let mut cases=Vec::new();
    let texts=["", " abc  def ghi ", "  a\n\n  b\nc", "中ab e\u{301} 👩‍🔬 x", "a\u{a0}b c\u{200b}d", "aaaaaaaa b cc", "\tA\rB\u{85}C", "e\u{301}👩‍🔬x"];
    for width in 0..=8 {for (ti,text) in texts.iter().enumerate() {for wrapping in 0..3 {for align in 0..3 {
        let height=3; let scroll=if ti%2==0 {(1,1)} else {(0,2)};
        let area=Rect::new(2,1,width,height);
        let mut b=Buffer::empty(Rect::new(0,0,width+4,height+2));
        for c in &mut b.content {c.set_symbol(".");}
        let line=Line::from(vec![Span::styled(*text,Style::new().fg(Color::Yellow).add_modifier(Modifier::ITALIC))]);
        // Preserve actual newlines through Text; alternate styled-span input exercises style precedence.
        let content=if ti%2==0 {Text::raw(*text)} else {Text::from(line)};
        let mut widget=Paragraph::new(content).style(Style::new().fg(Color::Red).bg(Color::Blue)).alignment(alignment(align)).scroll(scroll);
        if wrapping>0 {widget=widget.wrap(Wrap{trim:wrapping==2});}
        widget.render(area,&mut b);
        cases.push(json!({"kind":"paragraph","width":width,"height":height,"text":text,"styled":ti%2==1,
            "wrap":wrapping,"align":align,"scroll":[scroll.0,scroll.1],"cells":capture(&b)}));
    }}}}
    let values=["zero", "中 e\u{301}\nsecond", "two", "three\nline2\nline3", "four", "five"];
    for i in 0..360usize {
        let width=(i%10) as u16; let height=((i/10)%6) as u16;
        let selected=[None,Some(0),Some(2),Some(5),Some(99)][(i/7)%5];
        let offset=[0,2,99][(i/11)%3]; let padding=[0,1,3][(i/13)%3]; let dir=(i/17)%2;
        let hs=(i/19)%3; let repeat=i%2==0; let empty=i%29==0; let blocked=i%7==0;
        let area=Rect::new(2,1,width,height); let mut b=Buffer::empty(Rect::new(0,0,width+4,height+2));
        for c in &mut b.content {c.set_symbol(".");}
        let items=if empty {vec![]} else {values.iter().enumerate().map(|(j,s)| ListItem::new(*s).style(if j%2==0 {Style::new().fg(Color::Green)} else {Style::new()})).collect()};
        let mut widget=List::new(items).style(Style::new().fg(Color::Red).bg(Color::Blue))
            .highlight_style(Style::new().fg(Color::Yellow).add_modifier(Modifier::REVERSED))
            .highlight_symbol(Line::from(">").style(Style::new().fg(Color::Cyan))).repeat_highlight_symbol(repeat)
            .highlight_spacing(spacing(hs)).scroll_padding(padding)
            .direction(if dir==0 {ListDirection::TopToBottom} else {ListDirection::BottomToTop});
        if blocked {widget=widget.block(Block::bordered());}
        let mut state=ListState::default().with_selected(selected).with_offset(offset);
        StatefulWidget::render(widget,area,&mut b,&mut state);
        cases.push(json!({"kind":"list","width":width,"height":height,"selected":selected,"offset":offset,
            "padding":padding,"direction":dir,"spacing":hs,"repeat":repeat,"empty":empty,"block":blocked,
            "cells":capture(&b),"state":[state.offset(),state.selected()]}));
    }
    for i in 0..420usize {
        let width=(i%14) as u16; let height=((i/14)%6) as u16;
        let selected=[None,Some(0),Some(1),Some(3),Some(99)][(i/3)%5];
        let column=[None,Some(0),Some(1),Some(99)][(i/5)%4]; let offset=[0,2,99][(i/7)%3];
        let hs=(i/11)%3; let cs=(i/13)%3; let flex=(i/17)%7; let header=i%3==0; let footer=i%4==0;
        let margins=i%5==0; let spans=i%6==0; let empty=i%31==0; let explicit=i%2==0;
        let area=Rect::new(2,1,width,height); let mut b=Buffer::empty(Rect::new(0,0,width+4,height+2));
        for c in &mut b.content {c.set_symbol(".");}
        let rows=if empty {vec![]} else {vec![
            Row::new(vec![Cell::new("zero").column_span(if spans {2}else{1}),Cell::new("中a"),Cell::new("x")]).style(Style::new().fg(Color::Green)),
            Row::new(["one\nline2", "e\u{301}b\nsecond", "y"]).height(2).top_margin(if margins {1}else{0}),
            Row::new(["two","👩‍🔬","z"]).bottom_margin(if margins {1}else{0}),
            Row::new(["three\nline2\nline3","last", "!"]).height(3)]};
        let widths=if explicit {vec![Constraint::Length(3),Constraint::Min(2),Constraint::Fill(1)]} else {vec![]};
        let mut widget=Table::new(rows,widths).column_spacing(cs as u16).highlight_spacing(spacing(hs))
            .style(Style::new().fg(Color::Red).bg(Color::Blue)).highlight_symbol(">\nv")
            .row_highlight_style(Style::new().fg(Color::Yellow)).column_highlight_style(Style::new().bg(Color::Green))
            .cell_highlight_style(Style::new().add_modifier(Modifier::REVERSED))
            .flex([Flex::Legacy,Flex::Start,Flex::End,Flex::Center,Flex::SpaceBetween,Flex::SpaceAround,Flex::SpaceEvenly][flex]);
        if header {widget=widget.header(Row::new(["H0","H1","H2"]).style(Style::new().fg(Color::Cyan)).bottom_margin(if margins {1}else{0}));}
        if footer {widget=widget.footer(Row::new(["F0","F1","F2"]).style(Style::new().fg(Color::Magenta)).top_margin(if margins {1}else{0}));}
        let mut state=TableState::new().with_selected(selected).with_selected_column(column).with_offset(offset);
        StatefulWidget::render(widget,area,&mut b,&mut state);
        cases.push(json!({"kind":"table","width":width,"height":height,"selected":selected,"column":column,"offset":offset,
            "spacing":hs,"columnSpacing":cs,"flex":flex,"header":header,"footer":footer,"margins":margins,"spans":spans,
            "empty":empty,"explicit":explicit,"cells":capture(&b),"state":[state.offset(),state.selected(),state.selected_column()]}));
    }
    println!("{}",json!({"schema":1,"ratatui":"0.30.2","cases":cases}));
}
