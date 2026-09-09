import MacBook from "../components/MacBook";

/**
 * The device shot. Scroll into it and the lid lifts, so the app arrives rather
 * than merely sitting there.
 */
export default function Showcase() {
  return (
    <section className="overflow-hidden pb-10 pt-6">
      <div className="shell">
        <MacBook>
          <img
            src="/shot-home.png"
            alt="The Potret window open on a Mac: a gallery of captures grouped by day, with a sidebar and a capture toolbar."
            className="absolute left-1/2 top-[10.5%] h-[70%] w-auto -translate-x-1/2"
            style={{
              borderRadius: "0.6cqw",
              boxShadow: "0 3cqw 5cqw -2cqw rgba(0,0,0,.6)",
            }}
          />
        </MacBook>
      </div>
    </section>
  );
}
