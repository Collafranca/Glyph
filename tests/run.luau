--!strict
-- Lune test entrypoint. Add new `require` lines as modules grow.

local t = require("./framework")

require("./parser/Xml.spec")

return t.run()
