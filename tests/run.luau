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

return t.run()
