--!strict
-- Lune test entrypoint. Add new `require` lines as modules grow.

local t = require("./framework")

require("./parser/Xml.spec")
require("./parser/Color.spec")
require("./parser/Transform.spec")
require("./parser/PathData.spec")
require("./parser/Length.spec")
require("./parser/Style.spec")
require("./parser/Svg.spec")
require("./flatten/Bezier.spec")
require("./flatten/Arc.spec")
require("./flatten/Path.spec")
require("./flatten/Stroke.spec")

return t.run()
