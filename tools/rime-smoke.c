// rime-smoke: deploys a Rime user directory with the local librime (and its
// plugins) and prints what some key sequences produce.
//
//   rime-smoke <shared_dir> <user_dir> <log_dir> <keys>...
//
// Key sequences use librime's simulate_key_sequence syntax, e.g. "nihao",
// "nihao[" or "shi{Tab}".
#include <stdio.h>
#include <string.h>

#include "rime_api.h"

static void run(RimeApi* rime, RimeSessionId session, const char* keys) {
  rime->clear_composition(session);
  rime->simulate_key_sequence(session, keys);
  printf("%-12s =>", keys);

  RIME_STRUCT(RimeCommit, commit);
  if (rime->get_commit(session, &commit)) {
    printf(" commit「%s」", commit.text);
    rime->free_commit(&commit);
  }
  RIME_STRUCT(RimeContext, context);
  if (rime->get_context(session, &context)) {
    if (context.menu.page_no > 0) {
      printf(" page %d:", context.menu.page_no + 1);
    }
    for (int i = 0; i < context.menu.num_candidates; ++i) {
      const RimeCandidate* candidate = &context.menu.candidates[i];
      const char* comment = candidate->comment ? candidate->comment : "";
      printf(" %d.%s%s%s%s", i + 1, candidate->text, *comment ? "(" : "", comment, *comment ? ")" : "");
    }
    rime->free_context(&context);
  }
  printf("\n");
}

int main(int argc, char* argv[]) {
  if (argc < 4) {
    fprintf(stderr, "usage: %s <shared_dir> <user_dir> <log_dir> <keys>...\n", argv[0]);
    return 2;
  }
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = argv[1];
  traits.user_data_dir = argv[2];
  traits.log_dir = argv[3];
  traits.distribution_name = "ohmyrime";
  traits.distribution_code_name = "ohmyrime-smoke";
  traits.distribution_version = "0";
  traits.app_name = "rime.ohmyrime-smoke";

  RimeApi* rime = rime_get_api();
  rime->setup(&traits);
  rime->initialize(NULL);
  if (rime->start_maintenance(True)) {
    rime->join_maintenance_thread();
  }

  RimeSessionId session = rime->create_session();
  RIME_STRUCT(RimeStatus, status);
  if (rime->get_status(session, &status)) {
    printf("schema: %s (%s)\n", status.schema_id, status.schema_name);
    rime->free_status(&status);
  }
  for (int i = 4; i < argc; ++i) {
    run(rime, session, argv[i]);
  }
  rime->destroy_session(session);
  rime->finalize();
  return 0;
}
