import { describe, expect, it } from "vitest";
import { createBlackHoleEffect, createFreezeEffect } from "../src/factories";

describe("TileEffect Factories", () => {
  describe("createFreezeEffect", () => {
    it("should create freeze effect with visual config", () => {
      const effect = createFreezeEffect();

      expect(effect.type).toBe("freeze");
      expect(effect.active).toBe(true);
      expect(effect.config).toBeDefined();
      expect(effect.config?.visual).toBeDefined();
      expect(effect.config?.visual?.overlayTexture).toBe(
        "/assets/tile-effects/freeze/overlay.png",
      );
      expect(effect.config?.visual?.removalEmitter).toBe("freeze-removal");
    });

    it("should not have visualState (moved to tile.local)", () => {
      const effect = createFreezeEffect();
      expect(effect).not.toHaveProperty("visualState");
    });
  });

  describe("createBlackHoleEffect", () => {
    it("should create black hole effect with visual config", () => {
      const effect = createBlackHoleEffect();

      expect(effect.type).toBe("black_hole");
      expect(effect.active).toBe(true);
      expect(effect.config).toBeDefined();
      expect(effect.config?.visual).toBeDefined();
      expect(effect.config?.visual?.overlayTexture).toBe(
        "/assets/tile-effects/black-hole/overlay.png",
      );
      expect(effect.config?.visual?.overlayWidth).toBe(100);
      expect(effect.config?.visual?.overlayHeight).toBe(100);
    });

    it("should have default removalCost of 7 shards", () => {
      const effect = createBlackHoleEffect();
      expect(effect.config?.removalCost).toBe(7);
    });

    it("should allow custom removalCost", () => {
      const effect = createBlackHoleEffect(5);
      expect(effect.config?.removalCost).toBe(5);
    });

    it("should not have visualState (moved to tile.local)", () => {
      const effect = createBlackHoleEffect();
      expect(effect).not.toHaveProperty("visualState");
    });
  });
});
