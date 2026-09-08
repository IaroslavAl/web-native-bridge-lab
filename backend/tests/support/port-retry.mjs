export async function retryBindConflicts(run) {
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      return await run(attempt);
    } catch (error) {
      if (error.code !== 'EADDRINUSE' || error.syscall !== 'listen') throw error;
      if (attempt === 3) throw new Error('bind conflicts exhausted after 3 attempts', { cause: error });
    }
  }
}
