pub fn SandboxedNoAlloc(
    comptime Model: type,
    comptime Input: type,
    comptime Render: type,
) type {
    return struct {
        update: fn (Model, Input) Model,
        render: fn (Model) Render,

        const Self = @This();

        pub fn step(
            comptime self: Self,
            model: Model,
            input: Input,
        ) Model {
            return self.update(model, input);
        }

        pub fn run(
            comptime self: Self,
            model: Model,
            inputs: []const Input,
        ) Model {
            var curr_model = model;
            return for (inputs) |input| {
                curr_model = self.step(curr_model, input);
            } else curr_model;
        }

        pub fn view(
            comptime self: Self,
            model: Model,
        ) Render {
            return self.render(model);
        }
    };
}
