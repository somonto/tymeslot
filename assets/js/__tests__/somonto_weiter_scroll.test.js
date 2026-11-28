/**
 * Somonto fork: after a time is picked, the page glides to "Next step" when it
 * is out of sight (somonto_weiter_scroll.js).
 */
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest'
import {
  DURATION_MS,
  MARGIN_PX,
  WEITER_EVENT,
  easeInOutCubic,
  glideTo,
  installWeiterScroll,
  revealWeiter,
  weiterScrollTop
} from '../somonto_weiter_scroll'

describe('weiterScrollTop', () => {
  test('nothing when the button is wholly in view', () => {
    expect(weiterScrollTop({ top: 700, bottom: 750, viewportHeight: 812, scrollY: 0 })).toBeNull()
    expect(weiterScrollTop({ top: 0, bottom: 812, viewportHeight: 812, scrollY: 300 })).toBeNull()
  })

  test('below the window: its foot comes up to the margin above the bottom edge', () => {
    expect(weiterScrollTop({ top: 1180, bottom: 1230, viewportHeight: 812, scrollY: 100 }))
      .toBe(100 + 1230 - (812 - MARGIN_PX))
  })

  test('above the window: its top comes down to the margin', () => {
    expect(weiterScrollTop({ top: -200, bottom: -150, viewportHeight: 812, scrollY: 900 }))
      .toBe(900 - 200 - MARGIN_PX)
  })

  test('never above the page top, nothing for unusable input', () => {
    expect(weiterScrollTop({ top: -10, bottom: 40, viewportHeight: 812, scrollY: 0 })).toBe(0)
    expect(weiterScrollTop({ top: NaN, bottom: 40, viewportHeight: 812, scrollY: 0 })).toBeNull()
  })
})

describe('easeInOutCubic', () => {
  test('starts and ends still, halfway at half time', () => {
    expect(easeInOutCubic(0)).toBe(0)
    expect(easeInOutCubic(1)).toBe(1)
    expect(easeInOutCubic(0.5)).toBe(0.5)
    expect(easeInOutCubic(0.1)).toBeLessThan(0.1)
    expect(easeInOutCubic(2)).toBe(1)
  })
})

function fakeWindow({ reduce = false, scrollY = 0, innerHeight = 812, embedded = false } = {}) {
  const frames = []
  const listeners = {}
  const win = {
    scrollY,
    scrollX: 0,
    innerHeight,
    self: {},
    top: null,
    Element: window.Element,
    matchMedia: () => ({ matches: reduce }),
    scrollTo: vi.fn((a, b) => { win.scrollY = typeof a === 'object' ? a.top : b }),
    requestAnimationFrame: vi.fn((cb) => { frames.push(cb); return frames.length }),
    cancelAnimationFrame: vi.fn(),
    setTimeout: (cb) => { cb(); return 1 },
    addEventListener: vi.fn((type, cb) => { (listeners[type] ||= []).push(cb) }),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn()
  }
  win.top = embedded ? {} : win.self
  return { win, frames, listeners }
}

describe('glideTo', () => {
  test('glides over DURATION_MS with its own frames, ending exactly on target', () => {
    const { win, frames } = fakeWindow({ scrollY: 0 })
    glideTo(win, 400)
    frames.shift()(1000)
    expect(win.scrollY).toBe(0)
    frames.shift()(1000 + DURATION_MS / 2)
    expect(win.scrollY).toBe(200)
    frames.shift()(1000 + DURATION_MS)
    expect(win.scrollY).toBe(400)
    expect(frames).toHaveLength(0)
    expect(win.scrollTo).toHaveBeenCalledWith({ top: 400, left: 0, behavior: 'instant' })
  })

  test('reduced motion jumps without frames', () => {
    const { win, frames } = fakeWindow({ reduce: true })
    glideTo(win, 400)
    expect(frames).toHaveLength(0)
    expect(win.scrollY).toBe(400)
  })

  test('the visitor scrolling stops the glide', () => {
    const { win, frames, listeners } = fakeWindow()
    glideTo(win, 400)
    expect(Object.keys(listeners)).toEqual(expect.arrayContaining(['wheel', 'touchstart']))
    listeners.touchstart[0]()
    expect(win.cancelAnimationFrame).toHaveBeenCalled()
    expect(frames).toHaveLength(1)
  })
})

describe('revealWeiter', () => {
  let button
  beforeEach(() => {
    document.body.innerHTML = '<button data-testid="next-step">Weiter</button>'
    button = document.querySelector('button')
  })
  afterEach(() => { document.body.innerHTML = '' })

  const at = (top, bottom) => { button.getBoundingClientRect = () => ({ top, bottom }) }

  test('standalone: glides when out of sight, stays when in view', () => {
    const { win, frames } = fakeWindow()
    at(700, 750)
    revealWeiter(button, document, win)
    expect(frames).toHaveLength(0)
    at(1180, 1230)
    revealWeiter(button, document, win)
    expect(frames).toHaveLength(1)
  })

  test('inline embed: asks the embedding page, with the position in the document', () => {
    const { win } = fakeWindow({ embedded: true, scrollY: 0 })
    Object.defineProperty(document.documentElement, 'scrollHeight', { value: 400, configurable: true })
    at(1180.2, 1230.7)
    revealWeiter(button, document, win)
    const event = win.dispatchEvent.mock.calls[0][0]
    expect(event.type).toBe(WEITER_EVENT)
    expect(event.detail).toEqual({ top: 1180, bottom: 1231 })
  })
})

describe('installWeiterScroll', () => {
  test('only a click on a time in Design Quill, once the button is enabled', async () => {
    document.documentElement.classList.add('quill-theme')
    document.body.innerHTML =
      '<button data-testid="time-slot"><span id="t">10:00</span></button><button data-testid="next-step">Weiter</button>'
    const next = document.querySelector('[data-testid="next-step"]')
    next.getBoundingClientRect = () => ({ top: 1180, bottom: 1230 })
    const { win, frames } = fakeWindow()
    win.requestAnimationFrame = vi.fn((cb) => { frames.push(cb); return 1 })
    const uninstall = installWeiterScroll(document, win)

    document.body.click()
    await Promise.resolve()
    expect(frames).toHaveLength(0)

    document.getElementById('t').click()
    // resolve() waits one frame for the layout LiveView leaves
    await vi.waitFor(() => expect(frames.length).toBeGreaterThan(0))
    frames.shift()(0)
    await Promise.resolve()
    await Promise.resolve()
    expect(frames).toHaveLength(1)

    uninstall()
    document.documentElement.classList.remove('quill-theme')
  })
})
