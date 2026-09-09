import MacWindow from "../components/MacWindow";

/**
 * The two surfaces a capture reaches you through — the panel that appears the
 * moment you take one, and the corner stack holding the last few.
 *
 * Both shots share a fixed-height stage so the columns start and end together;
 * a wide panel beside a tall stack otherwise leaves one side hanging.
 */
const STAGE = 340;

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
            <MacWindow
              src="/shot-popup.png"
              alt="A small floating panel showing the capture just taken, with copy, save, annotate, pin and close buttons."
              title="Quick Access, right after a capture"
              stage={STAGE}
            />
          </div>

          <div className="reveal min-w-0" style={{ transitionDelay: "80ms" }}>
            <h3 className="text-[19px] font-medium">Hover the corner</h3>
            <p className="mt-2 min-h-[6.5rem] max-w-[46ch] text-[15px] text-slate">
              Push the pointer into the corner of your screen and the last few
              captures fan out, ready to drag into whatever you are writing. No
              window, no menu, no keystroke — and there is a menu-bar popup for
              the same thing if you prefer one.
            </p>
            <MacWindow
              src="/shot-corner.png"
              alt="A vertical stack of recent captures fanned out at the edge of the screen."
              title="The corner stack, on hover"
              stage={STAGE}
            />
          </div>
        </div>
      </div>
    </section>
  );
}
