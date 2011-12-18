#define PERL_NO_GET_CONTEXT

#include "hiredis.h"
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include <xs_object_magic.h>

#ifdef PERL_IMPLICIT_CONTEXT

#define dTHXREDIS(task)                     \
  dTHXa(task->privdata);

#define SET_THX_REDIS(r)                    \
  redisReplyReaderSetPrivdata(r, aTHX);

#else

#define dTHXREDIS(task)
#define SET_THX_REDIS(r)

#endif

static const char redisTypes[] = {
  [REDIS_REPLY_STRING]  = '$',
  [REDIS_REPLY_ARRAY]   = '*',
  [REDIS_REPLY_INTEGER] = ':',
  [REDIS_REPLY_NIL]     = '$',
  [REDIS_REPLY_STATUS]  = '+',
  [REDIS_REPLY_ERROR]   = '-'
};

static SV *createReply(pTHX_ SV *sv, int type)
{
  char reply_type = redisTypes[type];
  HV *reply = newHV();

  hv_stores(reply, "type", newSVpvn(&reply_type, sizeof reply_type));
  hv_stores(reply, "data", sv);
  return newRV_noinc((SV*)reply);
}

static void freeReplyObjectSV(void *reply) {
  dTHX;
  SV* r = reply;
  sv_2mortal(r);
}

static inline void storeParent(pTHX_ const redisReadTask *task, SV *reply)
{
  if (task->parent) {
    SV *const obj = task->parent->obj;
    HV *const parent = (HV*)SvRV(obj);
    SV **const data = hv_fetchs(parent, "data", FALSE);
    assert(data && SvTYPE(SvRV(*data)) == SVt_PVAV);
    av_store((AV*)SvRV(*data), task->idx, reply);
  }
}

static void *createStringObjectSV(const redisReadTask *task, char *str,
  size_t len)
{
  dTHXREDIS(task);

  SV *const reply = createReply(aTHX_ newSVpvn(str, len), task->type);
  storeParent(aTHX_ task, reply);
  return reply;
}

static void *createArrayObjectSV(const redisReadTask *task, int elements)
{
  dTHXREDIS(task);

  AV *av = newAV();
  SV *const reply = createReply(aTHX_ newRV_noinc((SV*)av), task->type);
  av_extend(av, elements);
  storeParent(aTHX_ task, reply);
  return reply;
}

static void *createIntegerObjectSV(const redisReadTask *task, long long value)
{
  dTHXREDIS(task);
  /* Not pretty, but perl doesn't always have a sane way to store long long in
   * a SV.
   */
#if defined(LONGLONGSIZE) && LONGLONGSIZE == IVSIZE
  SV *sv = newSViv(value);
#else
  SV *sv = newSVnv(value);
#endif

  SV *reply = createReply(aTHX_ sv, task->type);
  storeParent(aTHX_ task, reply);
  return reply;
}

static void *createNilObjectSV(const redisReadTask *task)
{
  dTHXREDIS(task);

  SV *reply = createReply(aTHX_ &PL_sv_undef, task->type);
  storeParent(aTHX_ task, reply);
  return reply;
}

/* Declarations below are used in the XS section */

static redisReplyObjectFunctions perlRedisFunctions = {
  createStringObjectSV,
  createArrayObjectSV,
  createIntegerObjectSV,
  createNilObjectSV,
  freeReplyObjectSV
};

static SV *encodeMessage(pTHX_ SV *message_p);

static SV *encodeString(pTHX_ SV *message_p) {
  HV *const message = (HV*)SvRV(message_p);
  SV **const type_sv = hv_fetchs(message, "type", FALSE);
  SV **const data_sv = hv_fetchs(message, "data", FALSE);

  char *type = SvPV_nolen(*type_sv);
  char *data = SvPV_nolen(*data_sv);

  return newSVpvf("%s%s\r\n", type, data);
};

static SV *encodeBulk(pTHX_ SV *message_p) {
  HV *const message = (HV*)SvRV(message_p);
  SV **const data_sv = hv_fetchs(message, "data", FALSE);

  if (!SvOK(*data_sv))
    return newSVpvf("$-1\r\n");

  STRLEN len;
  char *data = SvPV(*data_sv, len);

  return newSVpvf("$%u\r\n%s\r\n", len, data);
};

static SV *encodeMultiBulk (pTHX_ SV *message_p) {
  HV *const message = (HV*)SvRV(message_p);
  SV **const data_sv = hv_fetchs(message, "data", FALSE);

  if (!SvOK(*data_sv))
    return newSVpv("*-1\r\n", 0);

  AV *const data = (AV*)SvRV(*data_sv);
  I32 len = av_len(data);
  SV *r = newSVpvf("*%ld\r\n", len+1);

  I32 i;
  for (i = 0; i <= len; i++) {
    sv_catsv(r, encodeMessage(aTHX_ *av_fetch(data, i, FALSE)));
  };

  return r;
}

static SV *encodeMessage(pTHX_ SV *message_p) {
  HV *const message = (HV*)SvRV(message_p);
  SV **const type_sv = hv_fetchs(message, "type", FALSE);

  char *type = SvPV_nolen(*type_sv);
  const char op = type[0];

  if (1 != strlen(type) || NULL == strchr("+-:$*", op)) 
    croak("Unknown message type: \"%s\"", type);

  switch (op) {
    case '+':
    case '-':
    case ':':
      return encodeString(aTHX_ message_p);
    case '$':
      return encodeBulk(aTHX_ message_p);
    case '*':
      return encodeMultiBulk(aTHX_ message_p);
  }
}

typedef void reply_reader_t;

MODULE = Protocol::Redis::XS  PACKAGE = Protocol::Redis::XS
PROTOTYPES: ENABLE

void
_create(SV *self)
  PREINIT:
    reply_reader_t *r;
  CODE:
    r = redisReplyReaderCreate();
    if(redisReplyReaderSetReplyObjectFunctions(r, &perlRedisFunctions)
        != REDIS_OK) {
      redisReplyReaderFree(r);
      croak("Unable to set reply object functions");
    }
    SET_THX_REDIS(r);
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
      /* There's a callback, do parsing now. */
      SV *reply;
      do {
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
          sv_2mortal(reply);

          /* May free reply; we still use the presence of a pointer in the loop
           * condition below though.
           */
          FREETMPS;
          LEAVE;
        }
      } while(reply != NULL);
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

SV*
encode(SV *self, SV *message)
  CODE:
    RETVAL = encodeMessage(aTHX_ message);
  OUTPUT:
    RETVAL
