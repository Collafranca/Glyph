--!strict
-- Minimal zero-dependency test harness. Run via `lune run tests/run.luau`.
--
-- Usage:
--   local t = require("./framework")
--   t.suite("module", function()
--       t.test("does a thing", function()
--           t.expect(2 + 2).toEqual(4)
--       end)
--   end)
--   return t

local process = require("@lune/process")

type Test = {
	name: string,
	fn: () -> (),
}

type Suite = {
	name: string,
	tests: { Test },
}

type State = {
	suites: { Suite },
	currentSuite: Suite?,
	passed: number,
	failed: number,
	failures: { { suite: string, test: string, message: string } },
}

local state: State = {
	suites = {},
	currentSuite = nil,
	passed = 0,
	failed = 0,
	failures = {},
}

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in pairs(a :: any) do
		if not deepEqual(v, (b :: any)[k]) then
			return false
		end
	end
	for k in pairs(b :: any) do
		if (a :: any)[k] == nil then
			return false
		end
	end
	return true
end

local function reprValue(value: any, depth: number?): string
	local d = depth or 3
	if d <= 0 then
		return "<...>"
	end
	local tt = type(value)
	if tt == "string" then
		return string.format("%q", value)
	elseif tt == "table" then
		local parts = {}
		for k, v in pairs(value) do
			table.insert(parts, tostring(k) .. "=" .. reprValue(v, d - 1))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	else
		return tostring(value)
	end
end

type Expectation = {
	toEqual: (expected: any) -> (),
	toBe: (expected: any) -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
	toBeNil: () -> (),
	toThrow: (pattern: string?) -> (),
	toMatch: (pattern: string) -> (),
}

local T = {}

function T.expect(actual: any): Expectation
	local exp = {}
	function exp.toEqual(expected: any)
		if not deepEqual(actual, expected) then
			error("expected " .. reprValue(expected) .. ", got " .. reprValue(actual), 2)
		end
	end
	function exp.toBe(expected: any)
		if actual ~= expected then
			error("expected " .. reprValue(expected) .. ", got " .. reprValue(actual), 2)
		end
	end
	function exp.toBeTruthy()
		if not actual then
			error("expected truthy, got " .. reprValue(actual), 2)
		end
	end
	function exp.toBeFalsy()
		if actual then
			error("expected falsy, got " .. reprValue(actual), 2)
		end
	end
	function exp.toBeNil()
		if actual ~= nil then
			error("expected nil, got " .. reprValue(actual), 2)
		end
	end
	function exp.toThrow(pattern: string?)
		if type(actual) ~= "function" then
			error("toThrow requires a function, got " .. type(actual), 2)
		end
		local ok, err = pcall(actual :: () -> ())
		if ok then
			error("expected function to throw, but it returned normally", 2)
		end
		if pattern then
			local msg = tostring(err)
			if not string.find(msg, pattern) then
				error(
					"expected error to match " .. reprValue(pattern) .. ", got " .. reprValue(msg),
					2
				)
			end
		end
	end
	function exp.toMatch(pattern: string)
		if type(actual) ~= "string" then
			error("toMatch requires a string, got " .. type(actual), 2)
		end
		if not string.find(actual :: string, pattern) then
			error("expected " .. reprValue(actual) .. " to match " .. reprValue(pattern), 2)
		end
	end
	return exp
end

function T.suite(name: string, fn: () -> ())
	local suite: Suite = { name = name, tests = {} }
	table.insert(state.suites, suite)
	state.currentSuite = suite
	fn()
	state.currentSuite = nil
end

function T.test(name: string, fn: () -> ())
	local suite = state.currentSuite
	if not suite then
		-- Auto-wrap loose tests into a default suite.
		suite = { name = "(default)", tests = {} }
		table.insert(state.suites, suite)
		state.currentSuite = suite
	end
	table.insert((suite :: Suite).tests, { name = name, fn = fn })
end

function T.run(): number
	for _, suite in ipairs(state.suites) do
		print("\n" .. suite.name)
		for _, test in ipairs(suite.tests) do
			local ok, err = pcall(test.fn)
			if ok then
				state.passed += 1
				print("  \27[32mPASS\27[0m " .. test.name)
			else
				state.failed += 1
				table.insert(state.failures, {
					suite = suite.name,
					test = test.name,
					message = tostring(err),
				})
				print("  \27[31mFAIL\27[0m " .. test.name)
				print("    " .. tostring(err))
			end
		end
	end
	print(
		string.format(
			"\n%d passed, %d failed, %d total",
			state.passed,
			state.failed,
			state.passed + state.failed
		)
	)
	for _, failure in ipairs(state.failures) do
		print(string.format("\n  [%s] %s\n    %s", failure.suite, failure.test, failure.message))
	end
	if state.failed > 0 then
		process.exit(1)
	end
	return state.failed
end

return T
