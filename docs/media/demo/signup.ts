import { z } from "zod";

// Validate sign-up input before it reaches the API.
export const PASSWORD_RULE =
  /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?!.*(.)\1{2}).{12,64}$/;

export const SignupForm = z.object({
  email: z.string().email(),
  password: z.string().regex(PASSWORD_RULE, "Password doesn't meet the rules"),
  acceptTerms: z.literal(true),
});

export type SignupForm = z.infer<typeof SignupForm>;
