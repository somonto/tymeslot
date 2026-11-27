# Somonto-Fassung von Tymeslot

Geänderte Fassung von [Tymeslot](https://github.com/Tymeslot/tymeslot) (AGPL-3.0, siehe `LICENSE`), betrieben von der
Somonto e.U. für ihre Terminbuchung. Geändert ab 27.11.2026 auf Basis von `v1.41.0` (AGPL-3.0 § 5a). Keine offizielle
Tymeslot-Version.

## Zweige und Versionen

- `somonto`: Tymeslot-Tag plus die Somonto-Änderungen. `main` bleibt der Stand von Tymeslot.
- Image: `ghcr.io/somonto/tymeslot:<Tymeslot-Version>-somonto.<n>`, gebaut von `.github/workflows/somonto-image.yml`
  (nur `release-slim`, linux/amd64). Die übrigen Workflows von Tymeslot sind im Fork abgeschaltet.
- Nachziehen einmal im Monat: `somonto` auf den neuen Tag umsetzen (rebase), Tests der Somonto-Dateien laufen lassen,
  neues Image `…-somonto.1`. Sicherheitskorrekturen von Tymeslot sofort.

## Änderungen (Design Quill)

- Angaben in drei Seiten: „Ihre Angaben“ (Fragen außer Telefon, Name), „Kontakt“ (E-Mail, Telefonfragen), „Übersicht“
  (mit wem, wann samt Zeitzone als Name, Bestätigung an die E-Mail) mit „Gespräch buchen“; kein Nachrichtenfeld.
  `lib/tymeslot_web/themes/quill/scheduling/{live.ex,components/booking_component.ex}`
- Eine Buchungsseite mit genau einem Termintyp öffnet im Kalender, ohne Schritt „Dauer“; Foto und Begrüßung stehen dann
  über dem Kalender. `lib/tymeslot_web/themes/shared/somonto_steps.ex`
- Einbettung: Meldung `{ type: "tymeslot-step", step, index }` an die einbettende Seite bei jedem Schrittwechsel
  (gleiche Herkunftsprüfung wie `tymeslot-resize`). `assets/js/iframe_embed.js`
- Vorausfüllen per Anker zusätzlich `company` und `phone` (Antworten auf die Firmen- und Telefonfrage); `+` in `name`
  und `company` gilt als Leerzeichen. `assets/js/attendee_prefill.js`, `lib/tymeslot/scheduling/theme_flow.ex`,
  `lib/tymeslot_web/themes/shared/live_helpers/step_entry.ex`
- Fußzeile jeder Buchungsseite mit Link auf diesen Quelltext (AGPL-3.0 § 13). `…/shared/components/legal_links.ex`
- Tests: `test/tymeslot_web/live/themes/somonto_quill_details_test.exs`, JS-Tests in `assets/js/__tests__/`.
  Tests von Tymeslot, die den alten Quill-Ablauf (Fragen je Seite, Nachrichtenfeld) prüfen, gelten hier nicht.
