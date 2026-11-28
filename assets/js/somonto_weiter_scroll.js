/**
 * Somonto fork: once the visitor picks a time, the page glides slowly to the
 * "Next step" button (`data-testid="next-step"`), but only when that button is
 * out of sight. Design Quill only (`html.quill-theme`).
 *
 * - Standalone page (or a framed page whose own document scrolls): the page
 *   scrolls itself with its own requestAnimationFrame animation
 *   (`DURATION_MS`, ease-in-out), not `scroll-behavior`, whose speed the
 *   browser picks. Quill keeps the buttons sticky at the foot of a phone's
 *   window, so there it is usually in sight already and nothing moves.
 * - Inline embed (the frame as tall as the page): only the embedding page can
 *   scroll, and no animation crosses a cross-origin frame's edge. The page
 *   dispatches `WEITER_EVENT` with the button's top and bottom in the
 *   document; `iframe_embed.js` posts it to the embedding page as
 *   `{ type: "tymeslot-reveal", top, bottom }`, which scrolls the same way.
 *
 * "Reduce motion" jumps instead of gliding. A visitor's own scroll (wheel,
 * touch, key, pointer) ends the glide where it is. It only ever answers a
 * visitor's click on a time, never a page load.
 */

export const SLOT_SELECTOR = '[data-testid="time-slot"]'
export const NEXT_SELECTOR = '[data-testid="next-step"]'
export const WEITER_EVENT = "somonto:weiter-sichtbar"
/** Length of the glide: slow on purpose (Niklas 28.11.2026). */
export const DURATION_MS = 800
/** Room left under the button at the foot of the window. */
export const MARGIN_PX = 24
/** How long a click waits for LiveView to enable the button. */
export const ENABLE_WAIT_MS = 2000
const POLL_MS = 50
const OWN_SCROLL_EVENTS = ["wheel", "touchstart", "keydown", "pointerdown"]

export function easeInOutCubic(t) {
  const x = Math.min(1, Math.max(0, t))
  return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2
}

/**
 * The scroll position that brings a box (`top`/`bottom` relative to the
 * window) into view with `margin` below it, or null when it is in view
 * already. A box above the window comes down to `margin` under its top edge.
 */
export function weiterScrollTop({ top, bottom, viewportHeight, scrollY, margin = MARGIN_PX }) {
  if (![top, bottom, viewportHeight, scrollY, margin].every(Number.isFinite)) return null
  if (top >= 0 && bottom <= viewportHeight) return null
  const delta = top < 0 ? top - margin : bottom - (viewportHeight - margin)
  return Math.max(0, Math.round(scrollY + delta))
}

function prefersReducedMotion(win) {
  try {
    return !!(win.matchMedia && win.matchMedia("(prefers-reduced-motion: reduce)").matches)
  } catch (_) {
    return false
  }
}

function jumpTo(win, top) {
  try {
    win.scrollTo({ top, left: win.scrollX, behavior: "instant" })
  } catch (_) {
    win.scrollTo(win.scrollX, top)
  }
}

let cancelGlide = () => {}

/**
 * Scrolls `win` to `to` over `duration` ms with ease-in-out; jumps when the
 * visitor asked for reduced motion. Returns a function that stops it.
 */
export function glideTo(win, to, { duration = DURATION_MS, reduce = prefersReducedMotion(win) } = {}) {
  cancelGlide()
  const from = win.scrollY
  if (reduce || duration <= 0 || Math.abs(to - from) < 1) {
    jumpTo(win, to)
    return () => {}
  }
  let frame = null
  let start = null
  const stop = () => {
    if (frame !== null) win.cancelAnimationFrame(frame)
    frame = null
    OWN_SCROLL_EVENTS.forEach((type) => win.removeEventListener(type, stop))
  }
  const step = (now) => {
    if (start === null) start = now
    const t = (now - start) / duration
    jumpTo(win, Math.round(from + (to - from) * easeInOutCubic(t)))
    if (t < 1) frame = win.requestAnimationFrame(step)
    else stop()
  }
  OWN_SCROLL_EVENTS.forEach((type) => win.addEventListener(type, stop, { passive: true }))
  frame = win.requestAnimationFrame(step)
  cancelGlide = stop
  return stop
}

function documentScrolls(doc, win) {
  const root = doc.scrollingElement || doc.documentElement
  return root.scrollHeight > win.innerHeight + 1
}

/** Brings the button into view, or asks the embedding page to. */
export function revealWeiter(button, doc = document, win = window) {
  if (!button || !button.isConnected) return
  const rect = button.getBoundingClientRect()
  if (win.self !== win.top && !documentScrolls(doc, win)) {
    win.dispatchEvent(
      new CustomEvent(WEITER_EVENT, {
        detail: { top: Math.round(rect.top + win.scrollY), bottom: Math.round(rect.bottom + win.scrollY) }
      })
    )
    return
  }
  const to = weiterScrollTop({
    top: rect.top,
    bottom: rect.bottom,
    viewportHeight: win.innerHeight,
    scrollY: win.scrollY
  })
  if (to !== null) glideTo(win, to)
}

// The click lands before LiveView has answered; the button is enabled (and the
// layout final) only once the picked time is back from the server.
function whenEnabled(doc, win) {
  return new Promise((resolve) => {
    const startedAt = Date.now()
    const check = () => {
      const button = doc.querySelector(NEXT_SELECTOR)
      if (button && !button.disabled) {
        win.requestAnimationFrame(() => resolve(button))
      } else if (Date.now() - startedAt >= ENABLE_WAIT_MS) {
        resolve(null)
      } else {
        win.setTimeout(check, POLL_MS)
      }
    }
    win.setTimeout(check, POLL_MS)
  })
}

export function installWeiterScroll(doc = document, win = window) {
  const onClick = (event) => {
    const target = event.target
    if (!(target instanceof win.Element) || !target.closest(SLOT_SELECTOR)) return
    if (!doc.documentElement.classList.contains("quill-theme")) return
    whenEnabled(doc, win).then((button) => button && revealWeiter(button, doc, win))
  }
  doc.addEventListener("click", onClick)
  return () => doc.removeEventListener("click", onClick)
}
