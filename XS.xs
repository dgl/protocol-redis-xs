#include "hiredis.h"
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include <xs_object_magic.h>

typedef void reply_reader_t;

static SV *createReply(SV *sv, int type);
static void freeReplyObjectSV(void *reply);
static void *createStringObjectSV(const redisReadTask *task, char *str,
  size_t len);
static void *createArrayObjectSV(const redisReadTask *task, int elements);
static void *createIntegerObjectSV(const redisReadTask *task, long long value);
static void *createNilObjectSV(const redisReadTask *task);

static redisReplyObjectFunctions perlRedisFunctions = {
  createStringObjectSV,
  createArrayObjectSV,
  createIntegerObjectSV,
  createNilObjectSV,
  freeReplyObjectSV
};

static const char redisTypes[] = {
  [REDIS_REPLY_STRING]  = '$',
  [REDIS_REPLY_ARRAY]   = '*',
  [REDIS_REPLY_INTEGER] = ':',
  [REDIS_REPLY_NIL]     = '\0',
  [REDIS_REPLY_STATUS]  = '+',
  [REDIS_REPLY_ERROR]   = '-'
};

static SV *createReply(SV *sv, int type)
{
  char reply_type = redisTypes[type];
  HV *reply = newHV();

  hv_stores(reply, "type", reply_type
    ? newSVpvn(&reply_type, sizeof reply_type)
    : &PL_sv_undef);

  hv_stores(reply, "data", sv);

  return newRV_noinc((SV*)reply);
}

static void freeReplyObjectSV(void *reply) {
  SV* r = reply;
  sv_2mortal(r);
}

static inline void storeParent(const redisReadTask *task, SV *reply)
{
  if (task->parent) {
    SV *const obj = task->parent->obj;
    HV *const parent = SvRV(obj);
    SV **const data = hv_fetchs(parent, "data", FALSE);
    assert(data && SvTYPE(SvRV(*data)) == SVt_PVAV);
    av_store((AV*)SvRV(*data), task->idx, reply);
  }
}

static void *createStringObjectSV(const redisReadTask *task, char *str,
  size_t len)
{
  SV *const reply = createReply(newSVpvn(str, len), task->type);
  storeParent(task, reply);
  return reply;
}

static void *createArrayObjectSV(const redisReadTask *task, int elements)
{
  AV *av = newAV();
  SV *const reply = createReply(newRV_noinc((SV*)av), task->type);
  av_extend(av, elements);
  storeParent(task, reply);
  return reply;
}

static void *createIntegerObjectSV(const redisReadTask *task, long long value)
{
  /* Not pretty, but perl doesn't always have a sane way to store long long in
   * a SV.
   */
#if defined(LONGLONGSIZE) && LONGLONGSIZE == IVSIZE
  SV *sv = newSViv(value);
#else
  SV *sv = newSVnv(value);
#endif

  SV *reply = createReply(sv, task->type);
  storeParent(task, reply);
  return reply;
}

static void *createNilObjectSV(const redisReadTask *task)
{
  SV *reply = createReply(&PL_sv_undef, task->type);
  storeParent(task, reply);
  return reply;
}

MODULE = Protocol::Redis::XS  PACKAGE = Protocol::Redis::XS
PROTOTYPES: ENABLE

void
create(SV *self)
  PREINIT:
    reply_reader_t *r;
  CODE:
    r = redisReplyReaderCreate();
    if(redisReplyReaderSetReplyObjectFunctions(r, &perlRedisFunctions)
        != REDIS_OK) {
      redisReplyReaderFree(r);
      croak("Unable to set reply object functions");
    }
    xs_object_magic_attach_struct(aTHX_ SvRV(self), r);

void
DESTROY(reply_reader_t *r)
  CODE:
    redisReplyReaderFree(r);

void
parse(SV *self, SV *data)
  PREINIT:
    void *r;
    SV **callback;
  CODE:
    r = xs_object_magic_get_struct(aTHX_ SvRV(self));
    redisReplyReaderFeed(r, SvPVX(data), SvCUR(data));

    callback = hv_fetchs((HV*)SvRV(self), "_on_message_cb", FALSE);
    if (callback && SvOK(*callback)) {
      SV *reply;
      /* There's a callback, do parsing now. */
      if(redisReplyReaderGetReply(r, (void**)&reply) == REDIS_ERR) {
        croak("%s", redisReplyReaderGetError(r));
      }

      if (reply) {
        /* Call the callback */
        dSP;
        ENTER;
        SAVETMPS;
        PUSHMARK(SP);
        XPUSHs(self);
        XPUSHs(reply);
        PUTBACK;

        call_sv(*callback, G_DISCARD);

        FREETMPS;
        LEAVE;
      }
    }

SV*
get_message(reply_reader_t *r)
  CODE:
    if(redisReplyReaderGetReply(r, (void**)&RETVAL) == REDIS_ERR) {
      croak("%s", redisReplyReaderGetError(r));
    }
    if(!RETVAL)
      RETVAL = &PL_sv_undef;

  OUTPUT:
    RETVAL
