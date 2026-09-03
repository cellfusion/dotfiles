export function resolveProviderFamily(
  family: string,
  environment: string | undefined,
  configuredProviders: Iterable<string>,
): string {
  if (!environment || environment === "default") {
    return family;
  }

  const environmentProvider = `${family}-${environment}`;
  for (const provider of configuredProviders) {
    if (provider === environmentProvider) {
      return provider;
    }
  }
  return family;
}
