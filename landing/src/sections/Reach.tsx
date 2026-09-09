import Desktop from "../components/Desktop";

/**
 * The two surfaces a capture reaches you through — the panel that appears the
 * moment you take one, and the corner stack holding the last few.
 *
 * Both sit on a fabricated desktop rather than in a plain frame, because where
 * they appear on screen *is* the feature. A floating panel shown as a cropped
 * rectangle is just a toolbar; shown in the corner of a desktop it explains
 * itself. The desktop also gives both columns the same aspect, so they line up
 * without any height juggling.
 */
export default function Reach() {
  return (
    <section className="py-20">
      <div className="shell">
        <div className="reveal mx-auto max-w-[54ch] text-center">
          <p className="eyebrow">Always within reach</p>
          <h2 className="heading mt-3">
            Your last capture is never more than a nudge away.
          </h2>
        </div>

        <div className="mt-14 grid gap-12 lg:grid-cols-2">
          <div className="reveal min-w-0">
            <h3 className="text-[19px] font-medium">Quick Access</h3>
            <p className="mt-2 min-h-[6.5rem] max-w-[46ch] text-[15px] text-slate">
              Take a shot and a panel appears in the corner. Copy it, save it,
              annotate it, pin it — or drag it straight from the panel into
              Slack, Figma or a message. It never steals focus, and it follows
              you across Spaces.
            </p>
            <Desktop caption="Quick Access, right after a capture">
              <img
                src="/panel-popup.png"
                alt="A small floating panel in the lower-left corner of a Mac desktop, showing the capture just taken with copy, save, annotate and pin buttons."
                className="absolute bottom-[17%] left-[5%] w-[34%]"
                style={{ filter: "drop-shadow(0 12px 26px rgba(0,0,0,.5))" }}
              />
            </Desktop>
          </div>

          <div className="reveal min-w-0" style={{ transitionDelay: "80ms" }}>
            <h3 className="text-[19px] font-medium">Hover the corner</h3>
            <p className="mt-2 min-h-[6.5rem] max-w-[46ch] text-[15px] text-slate">
              Push the pointer into the corner of your screen and the last few
              captures fan out, ready to drag into whatever you are writing. No
              window, no menu, no keystroke — and there is a menu-bar popup for
              the same thing if you prefer one.
            </p>
            <Desktop caption="The corner stack, on hover">
              <img
                src="/panel-corner.png"
                alt="A vertical stack of recent captures fanned out against the left edge of a Mac desktop."
                className="absolute bottom-[17%] left-[4%] h-[68%] w-auto"
                style={{ filter: "drop-shadow(0 12px 26px rgba(0,0,0,.5))" }}
              />
            </Desktop>
          </div>
        </div>
      </div>
    </section>
  );
}
