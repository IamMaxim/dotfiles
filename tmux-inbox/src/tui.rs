//! ratatui popup: a small key->action state machine plus the event loop.

use crate::event::Event;

#[derive(Debug, PartialEq, Eq)]
pub enum Action {
    Jump(String),       // event id
    Dismiss(String),    // event id
    DismissAll,
    Quit,
    None,
}

pub struct TuiState {
    pub events: Vec<Event>, // newest last
    pub selected: usize,    // index into events
}

impl TuiState {
    pub fn new(mut events: Vec<Event>) -> TuiState {
        events.sort_by(|a, b| a.id.cmp(&b.id));
        let selected = events.len().saturating_sub(1); // start on newest
        TuiState { events, selected }
    }

    pub fn down(&mut self) {
        if self.selected + 1 < self.events.len() {
            self.selected += 1;
        }
    }

    pub fn up(&mut self) {
        self.selected = self.selected.saturating_sub(1);
    }

    fn current_id(&self) -> Option<String> {
        self.events.get(self.selected).map(|e| e.id.clone())
    }

    /// Map a single character keypress to an action.
    pub fn on_key(&mut self, c: char) -> Action {
        match c {
            'j' => { self.down(); Action::None }
            'k' => { self.up(); Action::None }
            '\n' | '\r' => self.current_id().map(Action::Jump).unwrap_or(Action::None),
            'd' => self.current_id().map(Action::Dismiss).unwrap_or(Action::None),
            'D' => Action::DismissAll,
            'q' => Action::Quit,
            _ => Action::None,
        }
    }
}

use crate::spool::Spool;
use crate::tmux;
use crossterm::event::{self as cevent, Event as CEvent, KeyCode};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::execute;
use ratatui::prelude::*;
use ratatui::widgets::{Block, Borders, List, ListItem, ListState, Paragraph};
use std::io;
use std::time::Duration;

/// Run the popup against the live spool. `here` filters to the current session.
pub fn run(spool: &Spool, bin: &str, here: bool) -> io::Result<()> {
    let panes = tmux::pane_map();
    let mut events = spool.list(crate::event::now_secs())?;
    if here {
        if let Some(cur) = tmux::current_pane().and_then(|p| panes.get(&p).map(|i| i.session.clone())) {
            events.retain(|e| {
                e.location.as_deref().and_then(|p| panes.get(p)).map(|i| i.session == cur).unwrap_or(false)
            });
        }
    }
    let mut state = TuiState::new(events);

    enable_raw_mode()?;
    let mut out = io::stdout();
    execute!(out, EnterAlternateScreen)?;
    let mut term = Terminal::new(CrosstermBackend::new(out))?;

    let result = event_loop(&mut term, &mut state, &panes, spool, bin);

    // Restore the terminal unconditionally — never let a failed cleanup step
    // skip the others and leave the terminal in a broken state.
    let _ = disable_raw_mode();
    let _ = execute!(term.backend_mut(), LeaveAlternateScreen);
    let _ = term.show_cursor();
    result
}

fn event_loop<B: Backend>(
    term: &mut Terminal<B>,
    state: &mut TuiState,
    panes: &std::collections::HashMap<String, tmux::PaneInfo>,
    spool: &Spool,
    bin: &str,
) -> io::Result<()> {
    let _ = bin;
    loop {
        term.draw(|f| draw(f, state, panes))?;
        if !cevent::poll(Duration::from_millis(250))? {
            continue;
        }
        if let CEvent::Key(k) = cevent::read()? {
            let c = match k.code {
                KeyCode::Char(c) => c,
                KeyCode::Enter => '\n',
                KeyCode::Down => 'j',
                KeyCode::Up => 'k',
                KeyCode::Esc => 'q',
                _ => continue,
            };
            match state.on_key(c) {
                Action::Quit => return Ok(()),
                Action::Jump(id) => {
                    if let Some(ev) = state.events.iter().find(|e| e.id == id) {
                        match ev.location.clone() {
                            Some(pane) => {
                                let _ = tmux::jump_to(&pane);
                                let _ = spool.dismiss_source(&ev.source);
                            }
                            None => {
                                // No pane to jump to; just clear this entry.
                                let _ = spool.dismiss_id(&id);
                            }
                        }
                    }
                    return Ok(());
                }
                Action::Dismiss(id) => {
                    let _ = spool.dismiss_id(&id);
                    state.events.retain(|e| e.id != id);
                    if state.selected >= state.events.len() {
                        state.selected = state.events.len().saturating_sub(1);
                    }
                    if state.events.is_empty() {
                        return Ok(());
                    }
                }
                Action::DismissAll => {
                    let _ = spool.dismiss_all();
                    return Ok(());
                }
                Action::None => {}
            }
        }
    }
}

fn draw(f: &mut Frame, state: &TuiState, panes: &std::collections::HashMap<String, tmux::PaneInfo>) {
    if state.events.is_empty() {
        let block = Block::default().borders(Borders::ALL).title(" inbox ");
        let para = Paragraph::new("\n  No notifications").block(block);
        f.render_widget(para, f.area());
        return;
    }
    let items: Vec<ListItem> = state.events.iter().rev().map(|e| {
        let loc = e.location.as_deref().and_then(|p| panes.get(p)).map(|i| format!("w{}", i.window)).unwrap_or_default();
        ListItem::new(format!("{} {:<6} {:<4} {}", e.level.glyph(), e.source, loc, e.message))
    }).collect();
    let title = format!(" inbox  {} ", state.events.len());
    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title(title))
        .highlight_symbol("\u{276f} ");
    let mut ls = ListState::default();
    // events render newest-first (reversed), so translate selected index.
    if !state.events.is_empty() {
        ls.select(Some(state.events.len() - 1 - state.selected));
    }
    f.render_stateful_widget(list, f.area(), &mut ls);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::{Event, Level};

    fn evs() -> Vec<Event> {
        vec![
            Event::new("a".into(), "codex".into(), None, Level::Info, 0),
            Event::new("b".into(), "claude".into(), None, Level::Attn, 0),
        ]
    }

    #[test]
    fn starts_on_newest() {
        let s = TuiState::new(evs());
        assert_eq!(s.events[s.selected].message, "b");
    }

    #[test]
    fn navigation_clamps() {
        let mut s = TuiState::new(evs());
        s.down(); // already at last
        assert_eq!(s.selected, 1);
        s.up();
        s.up(); // clamp at 0
        assert_eq!(s.selected, 0);
    }

    #[test]
    fn enter_jumps_current() {
        let mut s = TuiState::new(evs());
        let id = s.events[s.selected].id.clone();
        assert_eq!(s.on_key('\n'), Action::Jump(id));
    }

    #[test]
    fn d_dismisses_current_shift_d_all_q_quits() {
        let mut s = TuiState::new(evs());
        let id = s.events[s.selected].id.clone();
        assert_eq!(s.on_key('d'), Action::Dismiss(id));
        assert_eq!(s.on_key('D'), Action::DismissAll);
        assert_eq!(s.on_key('q'), Action::Quit);
    }
}
