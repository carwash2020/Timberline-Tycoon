# Trunk mesh rule for new tree species

A tree's trunk is built from sections that the game cuts, splits and resizes
at runtime (see `SectionLogic`, `SectionTrees`). A trunk mesh has to survive
that, so every new species follows this:

- A section is a plain upright: one straight piece, not a curved or forked one.
- Taper is 15 percent or less from bottom to top.
- Flat top and flat bottom, so two cut halves meet cleanly.
- The origin is at the centre of the section.
- No horizontal banding in the vertex colour. A resized stump stretches its
  mesh, and banding stretches with it. Vertical grain is fine.
- The cut face stays a runtime part (`TreeArt.CutFace`, looked up through
  `TreeArt.FaceLook`), never baked into the mesh.

This changes no mesh. It is the rule for the ones still to come.
