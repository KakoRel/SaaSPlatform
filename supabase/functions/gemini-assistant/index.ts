// Supabase Edge Function: gemini-assistant
// Deploy:
//   supabase functions deploy gemini-assistant
// Set secret:
//   supabase secrets set GEMINI_API_KEY=...

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const SYSTEM_PROMPT = `
You are an expert writing assistant for product and business documents.
Goals:
1) Improve clarity and structure without changing the core meaning.
2) Keep terminology consistent.
3) Produce actionable and concise output in Russian unless the user asks otherwise.
4) If asked for summary, return structured bullet points.
5) Never invent facts not present in the text.
`.trim();

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: "GEMINI_API_KEY is not configured" }),
        {
          status: 500,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    const body = await req.json();
    const action = (body?.action ?? "improve") as string;
    const text = (body?.text ?? "") as string;
    const instruction = (body?.instruction ??
      "Сделай текст более понятным и структурированным") as string;
    const chatHistory = (body?.messages ?? []) as Array<{
      role: "user" | "assistant";
      content: string;
    }>;
    const userPrompt = (body?.prompt ?? "") as string;

    const prompt =
      action === "chat"
        ? [
          `SYSTEM:\n${SYSTEM_PROMPT}`,
          text ? `DOCUMENT CONTEXT:\n${text}` : "",
          chatHistory.length > 0
            ? `CHAT HISTORY:\n${chatHistory.map((m) => `${m.role}: ${m.content}`).join("\n")}`
            : "",
          `USER REQUEST:\n${userPrompt}`,
          "Return only the assistant response.",
        ].filter(Boolean).join("\n\n")
        : [
          `SYSTEM:\n${SYSTEM_PROMPT}`,
          `TASK:\n${instruction}`,
          `TEXT:\n${text}`,
          "Return improved text only.",
        ].join("\n\n");

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: prompt }] }],
        }),
      },
    );

    const json = await response.json();
    if (!response.ok) {
      return new Response(JSON.stringify({ error: json }), {
        status: 500,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const resultText =
      json?.candidates?.[0]?.content?.parts?.[0]?.text ??
      "Не удалось получить ответ от модели.";

    return new Response(JSON.stringify({ text: resultText }), {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ error: e instanceof Error ? e.message : String(e) }),
      {
        status: 500,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      },
    );
  }
});

