# Potret promo video

The Remotion project behind the promo video. Independent of the app — it only needs Node.

```bash
npm install
npm run preview   # Remotion Studio
npm run render    # → out/potret-promo.mp4
```

`public/home.png` is the screenshot the video uses; `staticFile("home.png")` resolves against `public/`.
