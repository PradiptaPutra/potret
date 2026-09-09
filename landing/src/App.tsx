import Nav from "./components/Nav";
import Hero from "./sections/Hero";
import Modes from "./sections/Modes";
import Features from "./sections/Features";
import Native from "./sections/Native";
import Download from "./sections/Download";
import Footer from "./sections/Footer";
import { useReveal } from "./lib/useReveal";

export default function App() {
  const ref = useReveal<HTMLDivElement>();

  return (
    <div ref={ref}>
      <Nav />
      <main id="top">
        <Hero />
        <Modes />
        <Features />
        <Native />
        <Download />
      </main>
      <Footer />
    </div>
  );
}
