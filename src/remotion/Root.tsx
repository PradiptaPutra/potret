import { Composition } from "remotion";
import { PotretPromo } from "./PotretPromo";

export const VIDEO_WIDTH = 1920;
export const VIDEO_HEIGHT = 1080;
export const VIDEO_FPS = 30;
export const VIDEO_DURATION = 810;

export function RemotionRoot() {
  return (
    <Composition
      id="potret-promo"
      component={PotretPromo}
      durationInFrames={VIDEO_DURATION}
      fps={VIDEO_FPS}
      width={VIDEO_WIDTH}
      height={VIDEO_HEIGHT}
      defaultProps={{}}
    />
  );
}
