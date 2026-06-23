import Grain from "./components/Grain";
import Nav from "./components/Nav";
import Hero from "./sections/Hero";
import Features from "./sections/Features";
import Workflow from "./sections/Workflow";
import Download from "./sections/Download";
import Support from "./sections/Support";
import Footer from "./sections/Footer";

export default function App() {
  return (
    <>
      <Grain />
      <Nav />
      <main id="top" className="relative">
        <Hero />
        <Features />
        <Workflow />
        <Download />
        <Support />
      </main>
      <Footer />
    </>
  );
}
